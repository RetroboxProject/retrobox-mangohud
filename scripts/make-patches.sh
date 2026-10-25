#!/usr/bin/env bash
# Turn the differential of a local MangoHud branch into patches/.
#
#   scripts/make-patches.sh REPO BASE_TAG BRANCH [--single]
#
# e.g. scripts/make-patches.sh /var/penguin/desarrollo/mangohud v0.8.4 v0.8.4_br
#
# It takes the NET difference BASE_TAG..BRANCH, so it does not matter how the
# branch got there (merges, fixups...). By default it writes one patch per
# changed file: when a future upstream tag touches a file, only the patch for
# that file can fail, and its name says where. --single writes one patch.
#
# The patches carry full blob ids and binary data, which is what the 3-way
# fallback in fetch.sh needs. patches/BASE records BASE_TAG.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
OUT="$(cd "${HERE}/.." >/dev/null 2>&1 && pwd -P)/patches"

REPO="${1:?usage: make-patches.sh REPO BASE_TAG BRANCH [--single]}"
BASE="${2:?usage: make-patches.sh REPO BASE_TAG BRANCH [--single]}"
BRANCH="${3:?usage: make-patches.sh REPO BASE_TAG BRANCH [--single]}"
MODE="${4:-per-file}"

git -C "${REPO}" rev-parse --verify -q "${BASE}^{commit}" >/dev/null \
    || { echo "make-patches.sh: ${BASE} not found in ${REPO}" >&2; exit 1; }
git -C "${REPO}" rev-parse --verify -q "${BRANCH}^{commit}" >/dev/null \
    || { echo "make-patches.sh: ${BRANCH} not found in ${REPO}" >&2; exit 1; }

find "${OUT}" -maxdepth 1 -name '*.patch' -delete
echo "${BASE}" > "${OUT}/BASE"

diff_args=(--binary --full-index --no-color --no-ext-diff -M "${BASE}" "${BRANCH}")

if [[ "${MODE}" == "--single" ]]; then
    git -C "${REPO}" diff "${diff_args[@]}" > "${OUT}/0001-retrobox-mangohud.patch"
    echo "make-patches.sh: wrote 1 patch"
    exit 0
fi

n=0
while IFS= read -r -d '' file; do
    n=$((n + 1))
    slug="$(printf '%s' "${file}" | tr '/ ' '--' | tr -c 'A-Za-z0-9._-' '-')"
    git -C "${REPO}" diff "${diff_args[@]}" -- "${file}" \
        > "${OUT}/$(printf '%04d' "${n}")-${slug}.patch"
done < <(git -C "${REPO}" diff -z --name-only -M "${BASE}" "${BRANCH}")
echo "make-patches.sh: wrote ${n} patches (base ${BASE})"
