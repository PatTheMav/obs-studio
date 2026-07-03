#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
if [[ -n "${RUNNER_DEBUG}" ]]; then
  set -x
fi

: "${CI:?}"

download-custom-assets() {
  case "${GITHUB_EVENT_NAME}" in
  workflow_dispatch)
    mkdir -p "${DESTINATION}"
    pushd "${DESTINATION}" > /dev/null

    local -A url_patterns=(
      [macos-arm64]='OBS-Studio-.+-macOS-Apple.dmg'
      [macos-intel]='OBS-Studio-.+-macOS-Intel.dmg'
      [windows-x64]='OBS-Studio-.+-Windows-x64.zip'
      [windows-arm64]='OBS-Studio-.+-Windows-arm64.zip'
    )

    local platform_tuple="${PLATFORM,,*}-${ARCHITECTURE,,*}"

    local url_regex="^https:\/\/.+\/.+\/${url_patterns["${platform_tuple}"]}$"

    if [[ "${CUSTOM_ASSET}" =~ ${url_regex} ]]; then
      local file_name="$(basename "${CUSTOM_ASSET}")"
      local file_root="${file_name%%.*}"
      local file_extension="${file_name#*.}"
      local custom_file_name="${file_root}-custom.${file_extension}"

      curl \
        --silent \
        --location \
        --output "${custom_file_name}"

      if [[ -r "${file_name}" ]]; then
        echo "::warning::Custom asset ${file_name} does not replace an existing release asset."
      else
        rm -rf "${file_name}"
      fi

      mv "${custom_file_name}" "${file_name}"
    else
      echo "::error::Unsupported custom asset url '${CUSTOM_ASSET}' provided."
      return 1
    fi

    popd > /dev/null
    ;;
  *)
    echo "::error::Custom asset download only available for 'workflow_dispatch' events."
    return 1
    ;;
  esac
}

download-custom-assets
