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

    if (( num_matches >= 4 )); then
      echo "Semantic version detected for ${GIT_REF}."
      {
        echo "version=${BASH_REMATCH[0]}"
        echo "major=${BASH_REMATCH[2]}"
        echo "minor=${BASH_REMATCH[3]}"
        echo "patch=${BASH_REMATCH[4]}"
        echo "is-valid-semver=true"
      } >> "${GITHUB_OUTPUT}"
      return 0
    fi

    if (( num_matches == 8 )); then
      echo "Semantic pre-release version detected for ${GIT_REF}."
      {
        echo "prerelease=${BASH_REMATCH[-2]}"
        echo "number=${BASH_REMATCH[-1]}"
        echo "is-valid-semver=true"
      } >> "${GITHUB_OUTPUT}"
      return 0
    fi
  fi
  echo "No semantic version detected for ${GIT_REF}."
  echo "is-valid-semver=false" >> "${GITHUB_OUTPUT}"
}

check-version-tag
