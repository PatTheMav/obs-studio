#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

check-version-tag() {
  local version_regex='^(([0-9]+)\.([0-9]+)\.([0-9]+))(-(rc|beta)([0-9]+))?$'

  if [[ "${GIT_REF}" =~ ${version_regex} ]]; then
    local -i num_matches="${#BASH_REMATCH[@]}"

    {
      if (( num_matches >= 4 )); then
        echo "version=${BASH_REMATCH[0]}"
        echo "major=${BASH_REMATCH[2]}"
        echo "minor=${BASH_REMATCH[3]}"
        echo "patch=${BASH_REMATCH[4]}"
      fi

      if (( num_matches == 8 )); then
        echo "prerelease=${BASH_REMATCH[-2]}"
        echo "number=${BASH_REMATCH[-1]}"
      fi

      echo "is-valid-semver=true"
    } >> "${GITHUB_OUTPUT}"
  else
    echo "is-valid-semver=false" >> "${GITHUB_OUTPUT}"
  fi
}

check-version-tag
