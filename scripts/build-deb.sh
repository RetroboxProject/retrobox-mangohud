#!/usr/bin/env bash
# Build the .deb from a built checkout.
#
#   scripts/build-deb.sh SRC OUTDIR
#
# Environment: PKG_REVISION  package revision, bumped per build (default 1)
#
# Version: <tag version>-<revision>~<distro tag>, e.g. 0.8.4-12~ubuntu24.04. A
# build of something that is not a release tag is <YYYYMMDD>.<HHMMSS>-<revision>~...
# (see mh_snapshot in common.sh).
#
# Architecture, as the file name ends (MICROARCH=v3 only on amd64):
#   amd64 -> ..._amd64.deb      amd64, v3 -> ..._amd64v3.deb      arm64 -> ..._arm64.deb
# amd64v3 is an architecture *variant* (as in Ubuntu 25.10+): the control file
# says "Architecture: amd64" plus "Architecture-Variant: amd64v3", so dpkg on
# any release installs it as a normal amd64 package.
#
# Runtime library dependencies are computed with dpkg-shlibdeps, so they use
# the package names of the distro the package was built on.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: build-deb.sh SRC OUTDIR}"
OUTDIR="${2:?usage: build-deb.sh SRC OUTDIR}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"
mkdir -p "${OUTDIR}"
OUTDIR="$(cd "${OUTDIR}" >/dev/null 2>&1 && pwd -P)"

mh_snapshot "${SRC}"

# shellcheck disable=SC1091
. /etc/os-release
case "${ID}" in
    debian) TAG="deb${VERSION_ID}" ;;
    ubuntu) TAG="ubuntu${VERSION_ID}" ;;
    *)      TAG="${ID}${VERSION_ID}" ;;
esac
ARCH="$(dpkg --print-architecture)"
FILE_ARCH="${ARCH}"
if [[ "${MICROARCH}" == v3 ]]; then
    [[ "${ARCH}" == amd64 ]] || { echo "build-deb.sh: MICROARCH=v3 needs amd64, not ${ARCH}" >&2; exit 1; }
    FILE_ARCH="amd64v3"
fi
VERSION="${MH_DEB_VERSION}-${PKG_REVISION:-1}~${TAG}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
PKGDIR="${WORK}/${PKG_NAME}_${VERSION}_${FILE_ARCH}"

"${HERE}/stage.sh" "${SRC}" "${PKGDIR}"

# --- shared-library dependencies --------------------------------------------
mkdir -p "${WORK}/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "${PKG_NAME}" "${PKG_NAME}" \
    > "${WORK}/debian/control"
elf_args=()
while IFS= read -r -d '' file; do
    if readelf -h "${file}" >/dev/null 2>&1; then
        elf_args+=("-e${file}")
    fi
done < <(find "${PKGDIR}${PREFIX}" -type f -print0)
[[ ${#elf_args[@]} -gt 0 ]] || { echo "build-deb.sh: no ELF files found" >&2; exit 1; }
SHLIBS="$(cd "${WORK}" && dpkg-shlibdeps -O --warnings=1 "${elf_args[@]}" \
    | sed -n 's/^shlibs:Depends=//p')"
[[ -n "${SHLIBS}" ]] || { echo "build-deb.sh: dpkg-shlibdeps found no dependencies" >&2; exit 1; }

# retrobox-core owns /opt/retrobox/resources and is the program that uses this.
DEPENDS="retrobox-core, ${SHLIBS}"

mkdir -p "${PKGDIR}/DEBIAN"
sed -e "s|@VERSION@|${VERSION}|g" -e "s|@ARCH@|${ARCH}|g" -e "s|@DEPENDS@|${DEPENDS}|g" \
    "${REPO_ROOT}/packaging/deb/control.in" > "${PKGDIR}/DEBIAN/control"
if [[ "${MICROARCH}" == v3 ]]; then
    sed -i '/^Architecture:/a Architecture-Variant: amd64v3' "${PKGDIR}/DEBIAN/control"
fi

OUT="${OUTDIR}/${PKG_NAME}_${VERSION}_${FILE_ARCH}.deb"
dpkg-deb --root-owner-group -Zxz --build "${PKGDIR}" "${OUT}"
echo "build-deb.sh: built ${OUT}"
echo "build-deb.sh: Depends: ${DEPENDS}"
