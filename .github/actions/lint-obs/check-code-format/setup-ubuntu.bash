#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

setup-ubuntu() {
  case "${LINTER_COMMAND:-}" in
    clang-format)
      brew install --quiet obsproject/tools/clang-format@22
      echo "/home/linuxbrew/.linuxbrew/opt/clang-format@22/bin" >> "${GITHUB_PATH}"
      ;;
    gersemi)
      brew install --quiet gersemi
      ;;
    swift-format)
      brew install --quiet swift-format
      ;;
    xmllint)
        sudo apt-get --quiet --quiet update
        sudo apt-get install --no-install-recommends --yes libxml2-utils
      ;;
    zizmor)
      brew install --quiet zizmor
      ;;
    *)
      return 1
  esac
}

setup-ubuntu
