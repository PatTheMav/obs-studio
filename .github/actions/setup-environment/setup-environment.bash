#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

shopt -s extglob

setup-buildconfig() {
  local config='RelWithDebInfo'
  local codesign='false'
  local package='false'
  local notarize='false'

  case "${GITHUB_EVENT_NAME}" in
    pull_request)
      local -i has_seeking_testers=0

      local json_data
      if json_data="$(gh pr view "${GITHUB_EVENT_NUMBER}" --json labels 2> /dev/null)"; then
        if jq --raw-output --exit-status \
          '.labels[] | select(.name == "Seeking Testers")' <<< "${json_data}"; then
          has_seeking_testers=1
        fi
      fi

      if (( has_seeking_testers )); then
        codesign='true'
        package='true'
      fi
      ;;
    push)
      codesign='true'
      package='true'

      local version_regex='^[0-9]+\.[0-9]+\.[0-9]+(-(rc|beta).+)?'
      if [[ "${GITHUB_REF_TYPE}" == 'tag' && "${GITHUB_REF_NAME}" =~ ${version_regex} ]]; then
        notarize='true'
        config='Release'
      fi
      ;;
    workflow_dispatch)
      codesign='true'
      ;;
    schedule)
      codesign='true'
      package='true'
      ;;
    *)
      ;;
  esac

  {
    echo "config=${config}"
    echo "codesign=${codesign}"
    echo "package=${package}"
    echo "notarize=${notarize}"
  } >> "${GITHUB_OUTPUT}"
}

setup-environment() {
  setup-buildconfig

  {
    if [[ "${GITHUB_EVENT_NAME}" == 'release' ]]; then
        case "${GITHUB_REF_NAME}" in
          +([0-9]).+([0-9]).+([0-9]) )
            echo "valid-version-tag=true"
            echo "obs-update-channel=stable"
            ;;
          +([0-9]).+([0-9]).+([0-9])-@(beta|rc)+([0-9]) )
            echo "valid-version-tag=true"
            echo "obs-update-channel=beta"
            ;;
          *)
            echo "valid-version-tag=false"
            ;;
        esac
    else
      echo "valid-version-tag=false"
    fi

    echo "commit-hash=${GITHUB_SHA:0:9}"
    echo "output-name=obs-studio-${PLATFORM}-${TARGET}-${GITHUB_SHA:0:9}"
  }  >> "${GITHUB_OUTPUT}"
}

setup-environment
