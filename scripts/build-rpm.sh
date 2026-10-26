#!/usr/bin/env bash
# Build the .rpm from a built checkout.
#
#   scripts/build-rpm.sh SRC OUTDIR
#
# Environment: PKG_REVISION  package release number, bumped per build (default 1)
#
# Version <tag version>, release <revision>.<YYYYMMDD>.<HHMMSS>.fcNN (UTC date and
# time of the upstream commit), e.g. 0.8.4-12.20260527.140811.fc44. The file is
# named by rpmbuild with the Fedora convention, <name>-<version>-<release>.<arch>.rpm:
#   retrobox-mangohud-0.8.4-12.20260527.140811.fc44.aarch64.rpm
# Architecture, as the file name ends: x86_64 | x86_64_v3 | aarch64
# (MICROARCH=v3 -> x86_64_v3, a real RPM architecture). The rpm in the build
# container must know it; the script checks that before building.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: build-rpm.sh SRC OUTDIR}"
OUTDIR="${2:?usage: build-rpm.sh SRC OUTDIR}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"
mkdir -p "${OUTDIR}"
OUTDIR="$(cd "${OUTDIR}" >/dev/null 2>&1 && pwd -P)"

mh_snapshot "${SRC}"

if [[ "${MICROARCH}" == v3 ]]; then
    TARGET_CPU="x86_64_v3"
else
    TARGET_CPU="${HOST_CPU}"
fi
if [[ "$(rpm --eval '%{_target_cpu}' --target "${TARGET_CPU}-linux")" != "${TARGET_CPU}" ]]; then
    echo "build-rpm.sh: this rpm ($(rpm --version)) does not know the architecture ${TARGET_CPU}" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

"${HERE}/stage.sh" "${SRC}" "${WORK}/stage"

rpmbuild -bb "${REPO_ROOT}/packaging/rpm/${PKG_NAME}.spec" \
    --target "${TARGET_CPU}-linux" \
    --define "_topdir ${WORK}/rpmbuild" \
    --define "_rpmdir ${OUTDIR}" \
    --define "mh_version ${MH_RPM_VERSION}" \
    --define "pkg_revision ${PKG_REVISION:-1}${MH_REV_DATE}" \
    --define "stage ${WORK}/stage"

find "${OUTDIR}" -name '*.rpm' -newer "${WORK}/stage" -print
