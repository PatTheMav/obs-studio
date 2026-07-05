#!/usr/bin/env bash
# shellcheck disable=SC2154,SC1091

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

setup-action() {
  echo '::group::Python Setup'
  if [[ "${RUNNER_OS}" == 'Linux' ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv || true)"
    echo "/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin" >> "${GITHUB_PATH}"
  fi

  brew install --quiet python3

  python3 -m venv "${RUNNER_TEMP}/compatibility-validator-venv"
  echo '::endgroup::'

  echo '::group::Install Action dependencies'
  source "${RUNNER_TEMP}/compatibility-validator-venv/bin/activate"
  python3 -m pip install --upgrade jsonschema json_source_map
  echo '::endgroup::'

  deactivate
}

setup-action
