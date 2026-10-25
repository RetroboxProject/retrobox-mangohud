#!/usr/bin/env bash
# Install the built package in a CLEAN container and check it.
#
#   tests/smoke.sh PACKAGE_FILE
#
# retrobox-core does not exist in any repository yet, so a stub package with
# that name satisfies the dependency; everything else (library packages...)
# must resolve from the distro's real repositories, which is what this test
# is for.
set -euo pipefail

PKG="$(realpath "${1:?usage: smoke.sh PACKAGE_FILE}")"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR}"' EXIT

fail() { echo "smoke.sh: FAIL: $*" >&2; exit 1; }

# --- the architecture of the package: file name and metadata -------------------
# MICROARCH (baseline | v3) tells which build this is.
MICROARCH="${MICROARCH:-baseline}"
case "${PKG}" in
    *.deb)
        host="$(dpkg --print-architecture)"
        label="${host}"
        [[ "${MICROARCH}" == v3 ]] && label="${host}v3"
        [[ "${PKG}" == *_"${label}".deb ]] || fail "the file name does not end in _${label}.deb"
        [[ "$(dpkg-deb -f "${PKG}" Architecture)" == "${host}" ]] || fail "Architecture is not ${host}"
        variant="$(dpkg-deb -f "${PKG}" Architecture-Variant)"
        if [[ "${MICROARCH}" == v3 ]]; then
            [[ "${variant}" == amd64v3 ]] || fail "Architecture-Variant is '${variant}', not amd64v3"
        else
            [[ -z "${variant}" ]] || fail "a baseline package must not have an Architecture-Variant"
        fi
        ;;
    *.rpm)
        label="$(uname -m)"
        [[ "${MICROARCH}" == v3 ]] && label="x86_64_v3"
        [[ "${PKG}" == *."${label}".rpm ]] || fail "the file name does not end in .${label}.rpm"
        [[ "$(rpm -qp --qf '%{ARCH}' "${PKG}")" == "${label}" ]] || fail "the rpm architecture is not ${label}"
        ;;
esac

case "${PKG}" in
    *.deb)
        export DEBIAN_FRONTEND=noninteractive
        mkdir -p "${STUB_DIR}/stub/DEBIAN"
        printf 'Package: retrobox-core\nVersion: 0\nArchitecture: all\nMaintainer: stub\nDescription: stub\n' \
            > "${STUB_DIR}/stub/DEBIAN/control"
        dpkg-deb --build "${STUB_DIR}/stub" "${STUB_DIR}/retrobox-core.deb" >/dev/null
        apt-get update
        apt-get install -y "${STUB_DIR}/retrobox-core.deb" "${PKG}"
        # Listed from the package file: container images exclude /usr/share/doc on install.
        FILES="$(dpkg-deb -c "${PKG}" | awk '{print $6}' | sed 's|^\./|/|; s|/$||')"
        ;;
    *.rpm)
        dnf install -y rpm-build
        cat > "${STUB_DIR}/stub.spec" <<'SPEC'
Name: retrobox-core
Version: 0
Release: 1
Summary: stub
License: MIT
BuildArch: noarch
%description
stub
%files
SPEC
        rpmbuild -bb "${STUB_DIR}/stub.spec" --define "_topdir ${STUB_DIR}/rpmbuild" >/dev/null
        stub_rpm=("${STUB_DIR}"/rpmbuild/RPMS/noarch/retrobox-core-*.rpm)
        if ! dnf install -y "${stub_rpm[@]}" "${PKG}"; then
            # dnf may not install a package of a microarchitecture arch such as
            # x86_64_v3 yet (support is still arriving): install what it needs by
            # capability, then the package itself with rpm.
            echo "smoke.sh: dnf refused ${PKG##*/}; installing its dependencies and using rpm" >&2
            dnf install -y "${stub_rpm[@]}"
            mapfile -t caps < <(rpm -qpR "${PKG}" | grep -vE '^(rpmlib\(|retrobox-core)' | sort -u)
            dnf install -y "${caps[@]}"
            rpm -Uvh "${PKG}"
        fi
        FILES="$(rpm -qpl "${PKG}")"
        ;;
    *) fail "unsupported package type: ${PKG}" ;;
esac

PREFIX=/opt/retrobox/resources/mangohud
LIBDIR="${PREFIX}/lib/mangohud/lib64"
LAYER_DIR="${PREFIX}/share/vulkan/implicit_layer.d"

[[ -x "${PREFIX}/bin/mangohud" ]]   || fail "${PREFIX}/bin/mangohud missing or not executable"
[[ -f "${LIBDIR}/libMangoHud.so" ]] || fail "libMangoHud.so missing from ${LIBDIR}"

# The wrapper must have the absolute libdir baked in, not ld.so's $LIB.
# shellcheck disable=SC2016  # a literal $LIB is what we look for
if grep -q '\$LIB' "${PREFIX}/bin/mangohud"; then
    fail "wrapper still uses \$LIB"
fi
# (the wrapper preloads libMangoHud_shim.so in recent releases, libMangoHud.so
# in older ones: accept any libMangoHud*.so from the private libdir)
if ! "${PREFIX}/bin/mangohud" env | grep -qE "^LD_PRELOAD=.*${LIBDIR}/libMangoHud[A-Za-z_]*\.so"; then
    "${PREFIX}/bin/mangohud" env | grep -E 'LD_PRELOAD|LD_LIBRARY_PATH' >&2 || true
    fail "wrapper does not preload a library from ${LIBDIR}"
fi

# Licence notices must travel with the binary (checked in the package itself).
DOC=/usr/share/doc/retrobox-mangohud
for f in copyright BUILDINFO licenses/MIT.txt licenses/mangohud.LICENSE licenses/imgui.LICENSE.txt \
         licenses/spdlog.LICENSE licenses/Apache-2.0.txt licenses/elfhacks.NOTICE licenses/nvml.NOTICE; do
    grep -qxF "${DOC}/${f}" <<<"${FILES}" || fail "${DOC}/${f} is not in the package"
done

# Exactly one Vulkan layer: Retrobox's, enabled by RETROBOX_MANGOHUD.
layers=("${LAYER_DIR}"/*.json)
[[ ${#layers[@]} -eq 1 ]] || fail "expected one layer JSON in ${LAYER_DIR}, found ${#layers[@]}"
layer="${layers[0]}"
grep -q '"VK_LAYER_RETROBOX_MANGOHUD_overlay_' "${layer}" || fail "layer name is not the Retrobox one"
grep -q '"RETROBOX_MANGOHUD": "1"' "${layer}" || fail "layer is not enabled by RETROBOX_MANGOHUD=1"
grep -q '"RETROBOX_MANGOHUD_DISABLE": "1"' "${layer}" || fail "layer has no RETROBOX_MANGOHUD_DISABLE"
lib_in_json="$(sed -n 's/.*"library_path": *"\([^"]*\)".*/\1/p' "${layer}")"
[[ -f "${lib_in_json}" ]] || fail "library_path ${lib_in_json} does not exist"

# Private: nothing outside the prefix except the environment.d file and docs,
# and no ldconfig registration.
stray="$(grep -vE "^(${PREFIX}(/|$)|/usr/lib/environment\.d(/64-retrobox-mangohud\.conf)?$|/usr/share/doc(/retrobox-mangohud(/.*)?)?$|/opt(/retrobox(/resources)?)?$|/usr(/lib|/share)?$|/\.?$)" <<<"${FILES}" || true)"
[[ -z "${stray}" ]] || fail "files outside the private prefix:
${stray}"
[[ ! -e /etc/ld.so.conf.d/mangohud.conf ]] || fail "the private libdir must not be registered with ldconfig"

# Every ELF file must resolve all its shared libraries in a clean system.
while IFS= read -r -d '' file; do
    if readelf -h "${file}" >/dev/null 2>&1 && ldd "${file}" 2>/dev/null | grep -q 'not found'; then
        ldd "${file}" | grep 'not found' >&2
        fail "unresolved shared libraries in ${file}"
    fi
done < <(find "${PREFIX}" -type f -print0)

echo "smoke.sh: OK (${PKG##*/})"
