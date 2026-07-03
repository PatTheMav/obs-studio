#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

shopt -s extglob

setup-ubuntu() {
  if [[ "${GITHUB_EVENT_NAME}" == 'release' ]]; then
      case "${GITHUB_REF_NAME}" in
        +([0-9]).+([0-9]).+([0-9]) )
          local last_prerelease
          last_prerelease="$(gh release list \
            --exclude-drafts \
            --limit 10 \
            --json 'publishedAt,tagName,isPrerelease' \
            --jq '[.[] | select(.isPrerelease == true)] | first | .tagName')"

          local current_release="${GITHUB_REF_NAME}"
          local -i is_prerelease_ahead=0

          local comparison_string
          comparison_string="$(printf '%s\n%s\n' "${current_release}" "${last_prerelease}")"
          if ! sort --version-sort --reverse --check=quiet <<< "${comparison_string}"; then
            is_prerelease_ahead=1
          fi

          # Handle edge case: Sort considers the non-suffixed version older than a suffixed one,
          # e.g. "1.0.0" is 'older' than "1.0.0-beta2". If major.minor.patch triple is identical,
          # consider current release more recent.
          if (( is_prerelease_ahead )) && [[ "${current_release}" == "${last_prerelease//-*}" ]]; then
            is_prerelease_ahead=0
          fi

          local flatpak_matrix
          if (( ! is_prerelease_ahead )); then
            flatpak_matrix='["beta", "stable"]'
          else
            flatpak_matrix='["stable"]'
          fi

          echo "flatpak-matrix=${flatpak_matrix}" >> "${GITHUB_OUTPUT}"
          ;;
        +([0-9]).+([0-9]).+([0-9])-@(beta|rc)*([0-9]) )
          echo 'flatpak-matrix=["beta"]' >> "${GITHUB_OUTPUT}"
          ;;
        *)
          ;;
      esac
  fi
}

setup-ubuntu
