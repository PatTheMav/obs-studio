#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

generate-checksums() {
  local jq_output
  jq_output="$(jq --raw-output '.[]' <<< "${RELEASE_FILES}")"

  {
    local file
    local shasum_output

    echo "### Checksums"
    while read -r file; do
      shasum_output="$(shasum --algorithm=256 "${file}")"
      read -r checksum _ <<< "${shasum_output}"
      echo "    ${file##*/}: ${checksum}"
    done <<< "${jq_output}"
  } > "${RUNNER_TEMP}/checksums.txt"

  echo "checksum-file=${RUNNER_TEMP}/checksums.txt" >> "${GITHUB_OUTPUT}"
}

generate-checksums
