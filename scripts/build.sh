#!/usr/bin/env bash
# Configure and build MangoHud (64-bit) from a patched checkout.
#
#   scripts/build.sh SRC
#
# The meson options are the ones the old retrobox installer used:
#   append_libdir_mangohud=false   libdir stays exactly lib/mangohud/lib64
#   dynamic_string_tokens=false    bake the absolute libdir into the `mangohud`
#                                  wrapper instead of relying on ld.so's $LIB,
#                                  which several launchers do not expand
#   with_xnvctrl=disabled          no proprietary-driver X dependency
#   mangoplot=disabled             upstream's log-plotting script: it needs python,
#                                  numpy, matplotlib and a Qt backend, none of which
#                                  Retrobox uses, and its `#!/usr/bin/env python`
#                                  shebang is rejected by rpmbuild on Fedora
# Only 64-bit is built: retrobox wraps 64-bit emulators only.
#
# Environment: MICROARCH  baseline (default) or v3, see common.sh. Each level
#                         uses its own build directory, SRC/build-<MICROARCH>.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: build.sh SRC}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"
BUILD="${SRC}/build-${MICROARCH}"

# meson takes its c_args / cpp_args from these at configure time, for the
# subprojects (imgui, spdlog, ...) too.
export CFLAGS="${CFLAGS:+${CFLAGS} }${MARCH_FLAGS}"
export CXXFLAGS="${CXXFLAGS:+${CXXFLAGS} }${MARCH_FLAGS}"

opts=(
    --prefix "${PREFIX}" --libdir "${LIBDIR_REL}" --buildtype=release
    -Dappend_libdir_mangohud=false
    -Dwith_xnvctrl=disabled
    -Ddynamic_string_tokens=false
    -Dwith_x11=enabled
    -Dwith_wayland=enabled
)
# Options present in some versions only.
if grep -q "'with_mangohud_next'" "${SRC}/meson_options.txt" 2>/dev/null; then
    opts+=(-Dwith_mangohud_next=false)
fi
if grep -q "'mangoplot'" "${SRC}/meson_options.txt" 2>/dev/null; then
    opts+=(-Dmangoplot=disabled)
fi

meson setup "${BUILD}" "${SRC}" "${opts[@]}"
verify_march "${BUILD}/compile_commands.json"
ninja -C "${BUILD}"
echo "build.sh: built ${BUILD}"
