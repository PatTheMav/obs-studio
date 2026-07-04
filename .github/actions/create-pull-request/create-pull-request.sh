#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

check-work-base() {
  if ! work_base_ref="$(git symbolic-ref --quiet --short HEAD)"; then
    if [[ -z "${BASE_REF}" ]]; then
      echo '::error::No source ref provided with checkout in detached HEAD mode.'
      return 1
    fi

    work_base_ref="$(git rev-parse HEAD)"
  fi
}

create-pull-request() {
  local work_base_ref
  check-work-base

  local base_ref="${BASE_REF:-"${work_base_ref}"}"

  # Target branch is either a new branch or deviates from existing target branch.
  # Force push the target branch to the remote.
  shopt -s extglob
  if [[ "${OUTCOME}" == @(new|deviated) ]]; then
    git push --force-with-lease origin "${BRANCH}:refs/heads/${BRANCH}"
  fi

  local pull_request_result='fail'

  # PR branch actually deviates from target branch, pull request should be created.
  if [[ "${DEVIATED:-false}" == 'true' ]]; then
    local pull_request_url
    if ! pull_request_url="$(gh pr create \
      --base "${base_ref}" \
      --head "${BRANCH}" \
      --title "${TITLE}" \
      --body "${BODY}" &> /dev/null)"; then

      # Pull request creation failed, check if pull request for the current author,
      # source branch, and target branch already exists.
      if pull_request_url="$(gh pr list \
        --base "${base_ref}" \
        --head "${BRANCH}" \
        --limit 1 \
        --json url --jq '.[].url')"; then
          # Existing pull request found, update content.
          gh pr edit "${pull_request_url##*\/}" \
            --base "${base_ref}" \
            --title "${TITLE}" \
            --body "${BODY}" &> /dev/null

          pull_request_result='updated'
      else
        echo '::error::Unable to create or edit pull request.'
        return 1
      fi
    else
      pull_request_result='created'
    fi

    {
      echo "pull-request-result=${pull_request_result}"
      echo "pull-request-number=${pull_request_url##*\/}"
      echo "pull-request-url=${pull_request_url}"
    }  >> "${GITHUB_OUTPUT}"
  else
    # If there are no deviations from the base branch, delete the target branch if requested.
    if [[ "${OUTCOME}" == @(even|deviated) ]]; then
      if [[ "${DELETE_UNUSED:-false}" == 'true' ]]; then
        git push --delete --force origin "refs/heads/${BRANCH}"
        echo 'pull-request-result=closed' >> "${GITHUB_OUTPUT}"
      fi
    fi
  fi
}

create-pull-request
