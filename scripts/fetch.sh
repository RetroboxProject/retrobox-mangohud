#!/usr/bin/env bash
# Fetch MangoHud at a given ref and apply patches/*.patch.
#
#   scripts/fetch.sh [--ref REF] [--no-patch] DEST
#
# REF is a tag, branch or commit id (default: $MH_REF, else the tag in
# patches/BASE).
#
# Resilience to upstream changes: each patch is applied as-is when it fits;
# when it does not (the file moved a few lines, or was touched upstream), the
# script falls back to a 3-way merge against patches/BASE, which is fetched
# too. A patch that cannot be merged stops the build and is named, together
# with the conflicting files.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/common.sh
. "${HERE}/common.sh"

REF="${MH_REF:-${PATCH_BASE}}"
APPLY=1
DEST=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref)      REF="${2:?--ref needs a value}"; shift 2 ;;
        --no-patch) APPLY=0; shift ;;
        -h|--help)  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         echo "fetch.sh: unknown option: $1" >&2; exit 2 ;;
        *)          DEST="$1"; shift ;;
    esac
done
[[ -n "${DEST}" ]] || { echo "usage: fetch.sh [--ref REF] [--no-patch] DEST" >&2; exit 2; }
if [[ -e "${DEST}" ]] && [[ -n "$(ls -A "${DEST}" 2>/dev/null)" ]]; then
    echo "fetch.sh: ${DEST} exists and is not empty" >&2
    exit 1
fi

mkdir -p "${DEST}"
git -C "${DEST}" init -q
git -C "${DEST}" remote add origin "${UPSTREAM_URL}"

# The base first (only its objects are needed, for the 3-way merge), then the
# target, which is what gets checked out.
if [[ "${REF}" != "${PATCH_BASE}" ]]; then
    git -C "${DEST}" fetch -q --depth 1 origin "refs/tags/${PATCH_BASE}:refs/tags/${PATCH_BASE}"
fi
if git -C "${DEST}" ls-remote --exit-code --tags origin "refs/tags/${REF}" >/dev/null 2>&1; then
    git -C "${DEST}" fetch -q --depth 1 origin "refs/tags/${REF}:refs/tags/${REF}"
    git -C "${DEST}" checkout -q "refs/tags/${REF}"
else
    git -C "${DEST}" fetch -q --depth 1 origin "${REF}"
    git -C "${DEST}" checkout -q FETCH_HEAD
fi
echo "${REF}" > "${DEST}/.git/retrobox-ref"
echo "fetch.sh: upstream ${REF} -> $(git -C "${DEST}" rev-parse --short=12 HEAD)"

[[ "${APPLY}" -eq 1 ]] || exit 0

shopt -s nullglob
patches=("${REPO_ROOT}"/patches/*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
    echo "fetch.sh: WARNING: patches/ is empty, building plain upstream" >&2
    exit 0
fi

git -C "${DEST}" config user.name retrobox
git -C "${DEST}" config user.email retrobox@localhost
err="$(mktemp)"
trap 'rm -f "${err}"' EXIT
for patch in "${patches[@]}"; do
    name="$(basename "${patch}")"
    if git -C "${DEST}" apply --check "${patch}" 2>"${err}"; then
        git -C "${DEST}" apply --whitespace=nowarn "${patch}"
        echo "fetch.sh: applied ${name}"
    elif git -C "${DEST}" apply --3way --whitespace=nowarn "${patch}" 2>"${err}"; then
        echo "fetch.sh: applied ${name} (3-way merge onto ${REF})"
    else
        echo "fetch.sh: ${name} does not apply to upstream ${REF}:" >&2
        cat "${err}" >&2
        git -C "${DEST}" diff --name-only --diff-filter=U | sed 's/^/  conflict in: /' >&2
        exit 1
    fi
done
