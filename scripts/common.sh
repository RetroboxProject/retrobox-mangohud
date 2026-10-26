#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are consumed by the scripts that source this file
# Shared settings for the packaging scripts. Meant to be sourced.

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/flightlessmango/MangoHud.git}"

PKG_NAME="retrobox-mangohud"

# Private prefix, the one retrobox-core looks for (MANGOHUD_PREFIX_DIR): it
# never shadows, nor is shadowed by, a MangoHud installed by the distro.
PREFIX="${PREFIX:-/opt/retrobox/resources/mangohud}"
LIBDIR_REL="lib/mangohud/lib64"

# --- target -------------------------------------------------------------------
# MICROARCH selects the CPU level of the build:
#   baseline  the default of the distribution (x86-64 on amd64, armv8-a on arm64)
#   v3        x86-64-v3 (AVX2, BMI2, FMA, ...): Intel Haswell / AMD Excavator
#             (2013-2015) or newer. x86_64 only.
# The architecture name that goes at the end of the package file is the one
# each distribution family uses:
#   .deb  amd64 | amd64v3 | arm64          .rpm  x86_64 | x86_64_v3 | aarch64
MICROARCH="${MICROARCH:-baseline}"
HOST_CPU="$(uname -m)"
[[ "${HOST_CPU}" == arm64 ]] && HOST_CPU=aarch64
MARCH_FLAGS=""
case "${MICROARCH}" in
    baseline) ;;
    v3)
        if [[ "${HOST_CPU}" != x86_64 ]]; then
            echo "common.sh: MICROARCH=v3 only exists on x86_64 (this is ${HOST_CPU})" >&2
            exit 1
        fi
        MARCH_FLAGS="-march=x86-64-v3"
        ;;
    *)
        echo "common.sh: MICROARCH must be baseline or v3, not '${MICROARCH}'" >&2
        exit 1
        ;;
esac

# verify_march COMPILE_COMMANDS_JSON: every C/C++ unit must have been compiled
# with the flags of ${MICROARCH}: all of them with -march=x86-64-v3 for v3, none
# for baseline. (The ELF "ISA needed" note cannot prove it: it only reports v3
# when the code happens to use a v3-only instruction.)
verify_march() {
    python3 - "$1" "${MICROARCH}" <<'PYEOF2'
import json
import sys

path, microarch = sys.argv[1:3]
with open(path, encoding="utf-8") as handle:
    units = json.load(handle)
flag = "-march=x86-64-v3"
wrong, total = [], 0
for unit in units:
    if not unit["file"].endswith((".c", ".cc", ".cpp", ".cxx")):
        continue
    command = unit.get("command") or " ".join(unit.get("arguments", []))
    total += 1
    has = flag in command.split()
    if has != (microarch == "v3"):
        wrong.append(unit["file"])
if total == 0:
    sys.exit("verify_march: no C/C++ units found in " + path)
if wrong:
    sys.exit(f"verify_march: {len(wrong)} of {total} units were not built for "
             f"MICROARCH={microarch}, e.g. {wrong[0]}")
print(f"verify_march: all {total} units built for MICROARCH={microarch}")
PYEOF2
}

# Absolute path of the repository root.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"

# The upstream tag patches/ was made against. Used to 3-way merge the patches
# onto a newer upstream, see fetch.sh.
PATCH_BASE="$(tr -d '[:space:]' < "${REPO_ROOT}/patches/BASE")"

# mh_snapshot SRC: describes the upstream ref of a checkout made by fetch.sh.
# Everything comes from the COMMIT the ref points to (UTC), not from the build
# date, so rebuilding the same ref gives the same version. Sets:
#   MH_REF                 the ref that was asked for (v0.8.4, master, ...)
#   MH_DATE / MH_TIME      YYYYMMDD / HHMMSS
#   MH_STAMP               YYYYMMDD_HHMMSS
#   MH_SHA / MH_SHA_FULL   7-char / full commit id
#   MH_DEB_VERSION         0.8.4              (a release tag: the tag's version)
#                          20260527.142530    (anything else: date.time of the commit)
#   MH_RPM_VERSION         same as MH_DEB_VERSION
# A Debian version cannot contain "_", so the stamp is written with a dot. The
# commit id and the date of a release tag are in BUILDINFO and in the release.
mh_snapshot() {
    local src="$1" ct
    MH_REF="$(cat "${src}/.git/retrobox-ref")"
    ct="$(git -C "${src}" log -1 --format=%ct)"
    MH_DATE="$(date -u -d "@${ct}" +%Y%m%d)"
    MH_TIME="$(date -u -d "@${ct}" +%H%M%S)"
    MH_STAMP="${MH_DATE}_${MH_TIME}"
    MH_SHA="$(git -C "${src}" rev-parse --short=7 HEAD)"
    MH_SHA_FULL="$(git -C "${src}" rev-parse HEAD)"
    if [[ "${MH_REF}" =~ ^v([0-9]+(\.[0-9]+)*)$ ]]; then
        MH_DEB_VERSION="${BASH_REMATCH[1]}"
    else
        MH_DEB_VERSION="${MH_DATE}.${MH_TIME}"
    fi
    MH_RPM_VERSION="${MH_DEB_VERSION}"
    SOURCE_DATE_EPOCH="${ct}"
    export MH_REF MH_DATE MH_TIME MH_STAMP MH_SHA MH_SHA_FULL MH_DEB_VERSION MH_RPM_VERSION SOURCE_DATE_EPOCH
}
