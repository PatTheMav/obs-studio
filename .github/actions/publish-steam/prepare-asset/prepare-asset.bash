#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

prepare-windows-asset() {
  mkdir -p "${RUNNER_TEMP}/steam-asset/steam-windows/scripts"
  pushd "${RUNNER_TEMP}/steam-asset/steam-windows" > /dev/null

  unzip -q "${ASSET}"
  rm "${ASSET}"

  cp -r "${GITHUB_ACTION_PATH}/scripts/windows" "${RUNNER_TEMP}/steam-asset/steam-windows/scripts"

  touch "${RUNNER_TEMP}/steam-asset/steam-windows/disable_updater"

  popd > /dev/null
}

prepare-macos-asset() {
  if [[ "${RUNNER_OS,,*}" != 'macos' ]]; then
    echo '::error::Preparing macOS Steam assets requires a macOS runner'
    return 1
  fi

  mkdir -p "${RUNNER_TEMP}/steam-asset/steam-macos/${ARCHITECTURE}/OBS.app"
  hdiutil attach \
    -noverify \
    -readonly \
    -noautoopen \
    -mountpoint /Volumes/obs-studio
    "${ASSET}"
  ditto /Volumes/obs-studio/OBS.app "${RUNNER_TEMP}/steam-asset/steam-macos/${ARCHITECTURE}/OBS.app"
  hdiutil unmount /Volumes/obs-studio

  cp -r "${GITHUB_ACTION_PATH}/scripts/macos/launch.sh" "${RUNNER_TEMP}/steam-asset/steam-macos/launch.sh"

  rm -r "${ASSET}"
}

prepare-asset() {
  mkdir -p "${RUNNER_TEMP}/steam-asset"

  local -A file_patterns=(
    [macos-arm64]='OBS-Studio-*-macOS-Apple.dmg'
    [macos-x86_64]='OBS-Studio-*-macOS-Intel.dmg'
    [windows-x64]='OBS-Studio-*-Windows-x64.zip'
    [windows-arm64]='OBS-Studio-*-Windows-arm64.zip'
  )
  local platform_tuple="${PLATFORM,,*}-${ARCHITECTURE,,*}"
  local expected_file_name="${file_patterns["${platform_tuple}"]}"

  if [[ ! -r "${ASSET}" && "${ASSET}" != */${expected_file_name} ]]; then
    echo "::error::Expected asset '${expected_file_name}' not found."
    return 1
  fi

  case "${PLATFORM,,*}" in
    windows) prepare-windows-asset ;;
    macos) prepare-macos-asset ;;
    *)
      echo "::error::Unsupported platform '${PLATFORM}'."
      return 1
      ;;
  esac

  echo "asset-path=${RUNNER_TEMP}/steam-asset" >> "${GITHUB_OUTPUT}"
}

prepare-asset
