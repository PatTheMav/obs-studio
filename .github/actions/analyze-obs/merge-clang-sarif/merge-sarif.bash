#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

merge-sarif() {
  if [[ ! -d "${SARIF_PATH}" ]]; then
    echo "::error::Provided path for SARIF files '${SARIF_PATH}' is not a directory."
    return 1
  fi

  local output
  output="$(compgen -G "${SARIF_PATH}/*.sarif")"

  local -a sarif_files=()
  while read -r file; do
    full_path="$(realpath "${file}")"
    sarif_files+=("${full_path}")
  done <<< "${output}"

  if (( ! ${#sarif_files[@]} )); then
    echo "::error::No SARIF files found in '${SARIF_PATH}'."
    return 1
  fi

  jq -s '{
    "$schema": first(.[]."$schema"),
    "version": first(.[].version),
    "runs": [{
      "tool": {
        "driver": (first(.[].runs[].tool.driver) | del(.rules)) + {
          "rules": reduce(.[].runs[].tool.driver.rules) as $obj ([]; . + $obj) | unique
        }
      },
      "artifacts": reduce(.[].runs[].artifacts) as $obj ([]; . + $obj) | unique,
      "results": (reduce(.[].runs[].results) as $obj ([]; . + $obj))
      | del(
        .[].codeFlows[].threadFlows[].locations[].location.physicalLocation.region.endLine,
        .[].codeFlows[].threadFlows[].locations[].location.physicalLocation.region.endColumn
        | select(. == 0)
      )
    }]
  }' "${sarif_files[@]}" > "${RUNNER_TEMP}/${OUTPUT_NAME}"

  echo "path=${RUNNER_TEMP}/${OUTPUT_NAME}" >> "${GITHUB_OUTPUT}"
}

merge-sarif
