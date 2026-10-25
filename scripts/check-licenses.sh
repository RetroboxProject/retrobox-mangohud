#!/usr/bin/env bash
# Fail if upstream carries third-party code or fonts that nobody has reviewed.
#
#   scripts/check-licenses.sh SRC      (SRC: a checkout that has been built, so
#                                       that meson has downloaded subprojects/)
#
# It checks that:
#   * the licence files that stage.sh copies into the package exist;
#   * every subproject, every entry of include/ and modules/, every embedded
#     font and every source file with a "Copyright" line is listed in
#     packaging/licenses-reviewed.txt.
#
# When it fails after an upstream update: read the licence of the new
# component, describe it in packaging/copyright, and list it in
# packaging/licenses-reviewed.txt. Set ALLOW_UNREVIEWED_LICENSES=1 to turn the
# failure into a warning (for a test build, never for a release).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

SRC="${1:?usage: check-licenses.sh SRC}"
SRC="$(cd "${SRC}" >/dev/null 2>&1 && pwd -P)"

problems=()

for file in LICENSE include/elfhacks.h include/nvml.h include/filesystem.h include/KHR/khrplatform.h; do
    [[ -f "${SRC}/${file}" ]] || problems+=("missing licence file: ${file}")
done

reviewed="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${REPO_ROOT}/packaging/licenses-reviewed.txt")"
# is_reviewed PATH: exact entry, or covered by an entry ending in "/".
is_reviewed() {
    local path="$1" entry
    while IFS= read -r entry; do
        [[ "${path}" == "${entry}" ]] && return 0
        [[ "${entry}" == */ && "${path}" == "${entry}"* ]] && return 0
    done <<<"${reviewed}"
    return 1
}

# Subprojects that are present as directories (not the .wrap files).
if [[ -d "${SRC}/subprojects" ]]; then
    while IFS= read -r -d '' dir; do
        name="$(basename "${dir}")"
        case "${name}" in packagecache|packagefiles) continue ;; esac
        [[ -n "$(find "${dir}" -type f -print -quit)" ]] || continue
        rel="subprojects/$(sed -E 's/-[0-9][0-9.]*$//' <<<"${name}")"
        is_reviewed "${rel}" || problems+=("unreviewed subproject: ${name}")
    done < <(find "${SRC}/subprojects" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# Vendored directories: every top-level entry must be covered.
for base in include modules; do
    [[ -d "${SRC}/${base}" ]] || continue
    while IFS= read -r -d '' entry; do
        rel="${base}/$(basename "${entry}")"
        if [[ -d "${entry}" ]]; then
            [[ -n "$(find "${entry}" -type f -print -quit)" ]] || continue
            is_reviewed "${rel}/" || is_reviewed "${rel}" || problems+=("unreviewed vendored directory: ${rel}")
        else
            is_reviewed "${rel}" || problems+=("unreviewed vendored file: ${rel}")
        fi
    done < <(find "${SRC}/${base}" -mindepth 1 -maxdepth 1 ! -name '.*' -print0)
done

# Embedded fonts.
while IFS= read -r -d '' file; do
    rel="${file#"${SRC}"/}"
    is_reviewed "${rel}" || problems+=("unreviewed embedded font: ${rel}")
done < <(find "${SRC}/src" "${SRC}/data" -type f \( -iname 'font*.c' -o -iname 'font*.h' -o -iname '*awesome*' \
            -o -name '*.ttf' -o -name '*.otf' \) ! -name 'font.cpp' -print0 2>/dev/null)

# Source files with a copyright notice (third-party code pasted into the tree).
while IFS= read -r -d '' file; do
    rel="${file#"${SRC}"/}"
    is_reviewed "${rel}" || problems+=("unreviewed file with a copyright notice: ${rel}")
done < <(grep -rIlZ 'Copyright' "${SRC}/src" "${SRC}/include" \
            --include='*.h' --include='*.hpp' --include='*.cpp' --include='*.c' || true)

if [[ ${#problems[@]} -gt 0 ]]; then
    printf 'check-licenses.sh: %s\n' "${problems[@]}" >&2
    echo "check-licenses.sh: review them, describe them in packaging/copyright and list them in packaging/licenses-reviewed.txt" >&2
    if [[ "${ALLOW_UNREVIEWED_LICENSES:-0}" == 1 ]]; then
        echo "check-licenses.sh: continuing because ALLOW_UNREVIEWED_LICENSES=1" >&2
        exit 0
    fi
    exit 1
fi
echo "check-licenses.sh: OK"
