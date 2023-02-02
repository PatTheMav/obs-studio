#!/bin/bash

set -euxo pipefail

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
: "${description:=}"
: "${assets_url:=}"
: "${tag_name:=}"
: "${commit_hash:=}"
: "${even_json:=}"

args=()

while true; do
  case "${1}" in
    --tag) tag_name="${2}"; shift 2 ;;
    --commit) commit_hash="${2}"; shift 2 ;;
    --) shift; args+=(${@}); break ;;
    *) echo "Unsupported option: '${1}'"; exit 2 ;;
  esac
done

case "${GITHUB_EVENT_NAME}" in
  release)
    event_json="${GITHUB_EVENT_PATH}"
    IFS=';' read -r description is_prerelease assets_url <<< \
      "$(jq -r '. | { tag_name, prelease, assets_url } | join (";")' "${event_json}")"

    curl -s "${assets_url}" -o asset_data.json
    ;;
  workflow_dispatch)
    if (( ! ${#tag_name} )); then
      echo "Missing tag name for non-release workflow run!"
      exit 2
    fi
    curl -s "${GITHUB_API_URL}/repos/obsproject/obs-studio/releases/tags/${tag_name}" -o tag_data.json
    event_json="${root_dir}/tag_data.json"

    IFS=';' read -r description is_prerelease assets_url <<< \
      "$(jq -r '. | { tag_name, prelease, assets_url } | join (";")' "${event_json}")"

    curl -s "${assets_url}" -o asset_data.json
    ;;
  schedule)
    if (( ! ${#commit_hash} )); then
      echo "Missing commit hash for nightly workflow fun!"
      exit 2
    fi
    is_prerelease='false'
    description="g${commit_hash}"
    echo "description=${description}" >> $GITHUB_OUTPUT
    echo "is_prerelease=${is_prerelease}" >> $GITHUB_OUTPUT
    exit 0
    ;;
  *) echo "Unsupported workflow event: ${GITHUB_EVENT_NAME}"; exit 2 ;;
esac

read -r windows_asset_url macos_apple_asset_url macos_intel_asset_url <<< \
  "$(jq -r '.[] | select(.name|test(".*(macos|Full-x64).*")) | .browser_download_url' asset_data.json \
    | sort -V \
    | tr '\n' ' ')"

: "${windows_display_name:=Windows x64}"
: "${macos_apple_display_name:=macOS Apple Silicon}"
: "${macos_intel_display_name:=macOS Intel}"

for platform in windows macos_apple macos_intel; do
  display_name="${platform}_display_name"
  custom_name="${platform}_asset_custom_url"
  name="${platform}_asset_url"
  if [[ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" && "${!custom_name}" ]]; then
    declare ${name}="${!custom_name}"
  fi

  if [[ -z ${!name} ]]; then
    echo "${!display_name} asset URL missing"
    exit 2
  fi
  echo "${name}=${!name}" >> $GITHUB_OUTPUT
done

echo "description=${description}" >> $GITHUB_OUTPUT
echo "is_prerelease=${is_prerelease}" >> $GITHUB_OUTPUT
