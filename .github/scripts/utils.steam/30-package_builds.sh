#!/bin/bash

set -euxo pipefail

shopt -s nullglob

pushd() {
  bultin pushd "${@}" > /dev/null
}

popd() {
  builtin popd "${@}" > /dev/null
}

if ! (( ${#CI} && ${#GITHUB_ACTION_PATH} )); then
  echo "${0} requires to be run by the steam-upload action"
fi

: "${root_dir:="$(pwd)"}"
: "${windows_asset_url:=}"
: "${macos_apple_asset_url:=}"
: "${macos_intel_asset_url:=}"
: "${github_token:="${GITHUB_TOKEN}"}"
: "${commit_hash:=}"

curl_opts=()
windows_opts=()
macos_apple_opts=()
macos_intel_opts=()

args=()

while true; do
  case "${1}" in
    --windows-asset) windows_asset_url="${2}"; shift 2 ;;
    --macos-apple-asset) macos_apple_url="${2}"; shift 2 ;;
    --macos-intel-asset) macos_intel_url="${2}"; shift 2 ;;
    --token) github_token="${2}"; shift 2 ;;
    --commit) commit_hash="${2}"; shift 2 ;;
    --) shift; args+=(${@}); break ;;
    *) echo "Unsupported option: '${1}'"; exit 2 ;;
  esac
done

case "${GITHUB_EVENT_NAME}" in
  release|workflow_dispatch)
    : "${windows_display_name:=Windows x64}"
    : "${macos_apple_display_name:=macOS Apple Silicon}"
    : "${macos_intel_display_name:=macOS Intel}"
    curl_opts+=(-L -H "Authorization: Bearer ${github_token}")

    for platform in windows macos_apple macos_intel; do
      display_name="${platform}_display_name"
      name="${platform}_asset_url"
      if [[ -z ${!name} ]]; then
        echo "${!display_name} asset URL missing"
        exit 2
      fi

      echo "::group::Download ${!display_name} builds"
      curl "${curl_opts[@]}" "${!name}" "${platform}.zip"
      echo "::endgroup::"
    done
    ;;
  schedule)
    if (( ! ${#commit_hash} )); then
      echo "Missing commit hash for nightly workflow fun!"
      exit 2
    fi
    windows_artifact_name="obs-studio-windows-x64-${commit_hash}"
    macos_arm64_artifact_name="obs-studio-macos-arm64-${commit_hash}"
    macos_intel_artifact_name="obs-studio-macos-x86_64-${commit_hash}"

    pushd "${root_dir}/nightlies"
    mv "${windows_artifact_name}/obs-studio-windows-x64-*.zip" "${root_dir}/windows.zip"
    mv "${macos_arm64_artifact_name}/obs-studio-*-macOS-Apple.dmg" "${root_dir}/mac_arm64.dmg"
    mv "${macos_intel_artifact_name}/obs-studio-*-macOS-Intel.dmg" "${root_dir}/mac_x86_64.dmg"
    ;;
  *)
    echo "Unsupported GitHub event name: ${GITHUB_EVENT_NAME}"
    exit 2
    ;;
esac

mkdir -p steam && pushd steam

echo '::group::Extract and prepare Windows x64'
mkdir -p steam-windows && pushd steam-windows
unzip "${root_dir}/windows.zip"

zip_files=(*.zip)
if (( ${#zip_files[@]} )); then
  unzip "${zip_files[@]}"
  rm "${zip_files[@]}"
fi

cp -r "${root_dir}/source/.github/scripts/utils.steam/scripts_windows" scripts
touch disable_updater
popd
echo '::endgroup::'

echo '::group::Extract and prepare macOS Apple Silicon'
mkdir -p steam-macos/arm64 && pushd steam-macos/arm64
if [[ -f "${root_dir}/mac_arm64.dmg.zip" ]]; then
  unzip "${root_dir}/mac_arm64.dmg.zip"
  7zz x *.dmg -otmp_arm64 || true
  rm *.dmg
else
  7zz x "${root_dir}/mac_arm64.dmg" -otmp_arm64 || true
fi

if [[ -d tmp_arm64/OBS.app ]]; then
  mv tmp_arm64/OBS.app steam-macos/arm64
else
  mv tmp_arm64/*/OBS.app steam-macos/arm64
fi

popd
echo '::endgroup::'

echo '::group::Extract and prepare macOS Intel'
mkdir -p steam-macos/x86_64 && pushd steam-macos/x86_64
if [[ -f "${root_dir}/mac_x86_64.dmg.zip" ]]; then
  unzip "${root_dir}/mac_x86_64.dmg.zip"
  7zz x *.dmg -otmp_x86_64 || true
  rm *.dmg
else
  7zz x "${root_dir}/mac_x86_64.dmg" -otmp_x86_64 || true
fi

if [[ -d tmp_x86_64/OBS.app ]]; then
  mv tmp_x86_64/OBS.app steam-macos/x86_64
else
  mv tmp_x86_64/*/OBS.app steam-macos/x86_64
fi

popd
echo '::endgroup::'

cp "${root_dir}/source/.github/scripts/utils.steam/scripts_macos/launch.sh" steam-macos/launch.sh
popd
