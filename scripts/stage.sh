#!/usr/bin/env bash
# Lay out the installation tree of a built checkout into DESTDIR.
#
#   scripts/stage.sh SRC DESTDIR
#
# Layout (relative to DESTDIR):
#   /opt/retrobox/resources/mangohud/bin/mangohud                  wrapper
#   /opt/retrobox/resources/mangohud/lib/mangohud/lib64/*.so       libraries
#   /opt/retrobox/resources/mangohud/share/vulkan/implicit_layer.d/
#                                       RetroboxMangoHud.<arch>.json
#   /usr/lib/environment.d/64-retrobox-mangohud.conf
#   /usr/share/doc/retrobox-mangohud/{copyright,licenses/,patches/,BUILDINFO}
#
# Two deliberate differences from a plain `meson install`:
#   * Upstream's own MangoHud.<arch>.json layer is dropped and replaced by one
#     named VK_LAYER_RETROBOX_MANGOHUD_overlay_<arch>, switched on by
#     RETROBOX_MANGOHUD=1, so it cannot collide with a distro MangoHud.
#   * Nothing is registered with ldconfig: the private libdir must not be
#     visible to other programs. (The wrapper has the absolute path baked in.)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: stage.sh SRC DESTDIR}"
DESTDIR="${2:?usage: stage.sh SRC DESTDIR}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"

fail() { echo "stage.sh: $*" >&2; exit 1; }

# Refuse to package anything whose licence has not been reviewed.
"${HERE}/check-licenses.sh" "${SRC}"
mh_snapshot "${SRC}"

if [[ -e "${DESTDIR}" ]] && [[ -n "$(ls -A "${DESTDIR}" 2>/dev/null)" ]]; then
    fail "${DESTDIR} exists and is not empty"
fi
mkdir -p "${DESTDIR}"
DESTDIR="$(cd "${DESTDIR}" >/dev/null 2>&1 && pwd -P)"

DESTDIR="${DESTDIR}" meson install -C "${SRC}/build-${MICROARCH}" --no-rebuild >/dev/null
ROOT="${DESTDIR}${PREFIX}"
LAYER_DIR="${ROOT}/share/vulkan/implicit_layer.d"

# --- sanity: the wrapper must not rely on ld.so's $LIB ------------------------
[[ -x "${ROOT}/bin/mangohud" ]] || fail "no bin/mangohud was installed"
# shellcheck disable=SC2016  # a literal $LIB is what we look for
if grep -q '\$LIB' "${ROOT}/bin/mangohud"; then
    fail "bin/mangohud still contains \$LIB (dynamic_string_tokens not honoured?)"
fi
[[ -f "${ROOT}/${LIBDIR_REL}/libMangoHud.so" ]] || fail "libMangoHud.so not in ${LIBDIR_REL}"

# --- Vulkan layer: Retrobox's own, derived from the one upstream generated ---
shopt -s nullglob
upstream_layers=("${LAYER_DIR}"/MangoHud.*.json)
[[ ${#upstream_layers[@]} -gt 0 ]] || fail "upstream generated no Vulkan layer JSON"
for up in "${upstream_layers[@]}"; do
    arch="$(basename "${up}" .json)"
    arch="${arch#MangoHud.}"
    python3 - "${up}" "${LAYER_DIR}/RetroboxMangoHud.${arch}.json" "${arch}" <<'PYEOF'
import json
import sys

src, dst, arch = sys.argv[1:4]
with open(src, encoding="utf-8") as handle:
    data = json.load(handle)
layer = data["layer"]
layer["name"] = f"VK_LAYER_RETROBOX_MANGOHUD_overlay_{arch}"
layer["enable_environment"] = {"RETROBOX_MANGOHUD": "1"}
layer["disable_environment"] = {"RETROBOX_MANGOHUD_DISABLE": "1"}
with open(dst, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=4)
    handle.write("\n")
PYEOF
    rm -f "${up}"
done
rm -f "${LAYER_DIR}"/MangoHud*.json

# --- keep the Retrobox layer off outside Retrobox -----------------------------
# retrobox-core removes RETROBOX_MANGOHUD_DISABLE for the games it launches.
mkdir -p "${DESTDIR}/usr/lib/environment.d"
cat > "${DESTDIR}/usr/lib/environment.d/64-retrobox-mangohud.conf" <<'EOF2'
# Avoid a conflict between the system's MangoHud and Retrobox's on Vulkan apps.
RETROBOX_MANGOHUD_DISABLE=1
RETROBOX_MANGOHUD=0
EOF2

# --- strip, modes -------------------------------------------------------------
while IFS= read -r -d '' file; do
    if readelf -h "${file}" >/dev/null 2>&1; then
        strip --strip-unneeded "${file}"
    fi
done < <(find "${ROOT}" -type f -print0)
find "${DESTDIR}" -type d -exec chmod 755 {} +
find "${DESTDIR}" -type f ! -perm /111 -exec chmod 644 {} +
find "${DESTDIR}" -type f -perm /111 -exec chmod 755 {} +

# --- licences -----------------------------------------------------------------
# MIT (and the other licences of upstream and its bundled components) require
# the notices to travel with the binary: `copyright` summarises, licenses/
# carries the verbatim texts and notices.
DOC="${DESTDIR}/usr/share/doc/${PKG_NAME}"
LIC="${DOC}/licenses"
mkdir -p "${DOC}/patches" "${LIC}"

install -m 644 "${REPO_ROOT}/packaging/copyright" "${DOC}/copyright"
install -m 644 "${REPO_ROOT}"/licenses/*.txt "${LIC}/"
install -m 644 "${SRC}/LICENSE" "${LIC}/mangohud.LICENSE"

# Licence files of the subprojects that were built in (versions change, so
# the directory name is stripped of its version).
while IFS= read -r -d '' dir; do
    name="$(basename "${dir}")"
    case "${name}" in packagecache|packagefiles) continue ;; esac
    base="$(sed -E 's/-[0-9][0-9.]*$//' <<<"${name}")"
    while IFS= read -r -d '' file; do
        install -m 644 "${file}" "${LIC}/${base}.$(basename "${file}")"
    done < <(find "${dir}" -maxdepth 1 -type f \( -iname 'LICEN[CS]E*' -o -iname 'COPYING*' \) -print0)
    if [[ -d "${dir}/LICENSES" ]]; then
        while IFS= read -r -d '' file; do
            install -m 644 "${file}" "${LIC}/${base}.LICENSES.$(basename "${file}")"
        done < <(find "${dir}/LICENSES" -maxdepth 1 -type f -print0)
    fi
done < <(find "${SRC}/subprojects" -mindepth 1 -maxdepth 1 -type d -print0)

# Notices that live inside vendored headers: copy the comment block verbatim.
extract() { # extract OUT SRCFILE AWK_PROGRAM
    awk "$3" "${SRC}/$2" > "${LIC}/$1"
    [[ -s "${LIC}/$1" ]] || fail "could not extract the notice for $1 from $2"
    chmod 644 "${LIC}/$1"
}
extract elfhacks.NOTICE       include/elfhacks.h          '/\/\* elfhacks.h --/{f=1} f{print} f&&/\*\//{exit}'
extract nvml.NOTICE           include/nvml.h              'f==0&&/\/\*/{f=1} f{print} f&&/\*\//{exit}'
extract khrplatform.NOTICE    include/KHR/khrplatform.h   'f==0&&/\/\*/{f=1} f{print} f&&/\*\//{exit}'
extract ghc-filesystem.NOTICE include/filesystem.h        '/^\/\//{print; next} {exit}'

# --- patches and build information --------------------------------------------
install -m 644 "${REPO_ROOT}/patches/BASE" "${DOC}/patches/BASE"
shopt -s nullglob
for patch in "${REPO_ROOT}"/patches/*.patch; do
    install -m 644 "${patch}" "${DOC}/patches/"
done
cat > "${DOC}/BUILDINFO" <<EOF2
upstream: ${UPSTREAM_URL}
ref:      ${MH_REF}
commit:   ${MH_SHA_FULL}
date:     ${MH_STAMP} (UTC, commit date)
patches:  $(find "${REPO_ROOT}/patches" -name '*.patch' | wc -l) (made against $(cat "${REPO_ROOT}/patches/BASE"))
EOF2
chmod 644 "${DOC}/BUILDINFO"

echo "stage.sh: staged ${PREFIX} into ${DESTDIR}"
