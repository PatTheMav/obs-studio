#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

clean-caches() {
  local gh_output
  gh_output="$(gh api "repos/${GITHUB_REPOSITORY}/actions/caches" \
    --jq "
      .actions_caches.[]
      | select(.ref | test(\"${GIT_REF}\"))
      | select(.key | test(\"${CACHE_NAME}\"))
      | {id, key, ref}
      | join(\"|\")
  ")"

  local cache_key
  local cache_ref
  local -i deleted_amount=0
  local -i result=0

  while IFS="|" read -r _ cache_key cache_ref; do
    if [[ -n "${cache_key}" ]]; then
      if result=gh api -x DELETE "repos/${GITHUB_REPOSITORY}/actions/caches?key=${cache_key}" \
        --jq '.total_count' 2>/dev/null; then
        echo "Deleted cache entry '${cache_key}' for git ref '${cache_ref}'."

        deleted_amount=$(( deleted_amount + result ))
      else
        echo "::warning::Unable to delete cache entry '${cache_key}'."
      fi
    fi
  done <<< "${gh_output}"

  echo "cleaned=${deleted_amount}" >> "${GITHUB_OUTPUT}"
}

clean-caches
