#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

shopt -s extglob

run-validator() {
  local -a json_files=()

  local output
  if ! output="$(jq --raw-output '.[]' 2> /dev/null <<< "${JSON_FILES}")"; then
    output="$(compgen -G "${JSON_FILES}")"
  fi

  while read -r file; do
    full_path="$(realpath "${file}")"
    json_files+=("${full_path}")
  done <<< "${output}"

  if (( ! ${#json_files[@]} )); then
    echo '::error::No json files found to validate.'
    return 1
  fi

  source "${RUNNER_TEMP}/compatibility-validator-venv/bin/activate"
  pushd "${RUNNER_TEMP}" > /dev/null
  declare -x PYTHONUNBUFFERED=1
  python3 "${GITHUB_ACTION_PATH}/check-jsonschema.py" \
    --loglevel INFO \
    "${json_files[@]}"
  popd > /dev/null

  deactivate
}

run-validator
