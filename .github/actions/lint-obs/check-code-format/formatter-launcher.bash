#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

formatter-launcher() {
  local checkout="${PWD}"

  if [[ "${FAIL_MODE:-never}" == 'never' ]]; then set +e; fi

  local jq_output
  jq_output="$(jq -r '.[]' <<< "${CHANGED_FILES}")"

  local change
  local -a changes
  while read -r change; do
    changes+=("${change}")
  done <<< "${jq_output}"

  local launcher
  if [[ "${RUNNER_OS}" == 'Linux' ]]; then
    launcher="${checkout}/build-aux/.run-format.bash"
  else
    launcher="${checkout}/build-aux/.run-format.zsh"
  fi

  ${launcher} \
    --linter "${LINTER_COMMAND}" \
    --check \
    --github \
    "${changes[@]}"
}

formatter-launcher
