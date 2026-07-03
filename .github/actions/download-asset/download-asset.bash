#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

download-release-asset() {
  download_pattern="${release_patterns["${platform_tuple}"]}"

  gh release download "${TAG_NAME}" \
    --pattern "${download_pattern}" \
    --clobber
}

download-tag-asset() {
  download_pattern="${release_patterns["${platform_tuple}"]}"

  if [[ "${TAG_NAME}" =~ [0-9]+\.[0-9]+\.[0-9]+(-(rc|beta)[0-9]+)*$ ]]; then
    gh release download "${TAG_NAME}" \
      --pattern "${download_pattern}" \
      --clobber
  else
    echo "::error::Invalid tag name '${TAG_NAME} for workflow dispatch event."
    return 1
  fi
}

download-nightly-asset() {
  download_pattern="${artifact_patterns["${platform_tuple}"]}"

  gh run download "${GITHUB_RUN_ID}" \
    --pattern "${download_pattern}"
}

download-assets() {
  local -A release_patterns=(
    [macos-arm64]='OBS-Studio-*-macOS-Apple.dmg'
    [macos-intel]='OBS-Studio-*-macOS-Intel.dmg'
    [windows-x64]='OBS-Studio-*-Windows-x64.zip'
    [windows-arm64]='OBS-Studio-*-Windows-arm64.zip'
  )

  local -A artifact_patterns=(
    [macos-arm64]='obs-studio-macos-arm64-*'
    [macos-intel]='obs-studio-macos-x86_64-*'
    [windows-x64]='obs-studio-windows-x64-*'
    [windows-arm64]='obs-studio-windows-arm64-*'
  )

  local platform_tuple="${PLATFORM,,*}-${ARCHITECTURE,,*}"

  mkdir -p "${DESTINATION}"
  pushd "${DESTINATION}" > /dev/null

  local download_pattern
  case "${GITHUB_EVENT_NAME}" in
  release) download-release-asset ;;
  workflow_dispatch) download-tag-asset ;;
  schedule) download-nightly-asset ;;
  *)
    echo "::error::Unsupported GitHub event name '${GITHUB_EVENT_NAME}'"
    return 1
    ;;
  esac

  local found_files=("${PWD}/${download_pattern}")
  if (( ! ${#found_files[@]} )); then
    echo "::warning::No downloaded files found with pattern '${download_pattern}'."
    echo "path=${PWD}/${found_files[0]}"
  fi

  popd > /dev/null
}

download-assets
