#!/usr/bin/env bash
# shellcheck disable=SC2154

set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

shopt -s extglob

rename-assets() {
  local -A platform_suffixes=(
    [macos-arm64]=macOS-Apple.dmg
    [macos-arm64-debug-symbols]=macOS-Apple-dSYMs.tar.xz
    [macos-arm64-plugin-dev]=macOS-Apple-Libraries.tar.xz
    [macos-x86_64]=macOS-Intel.dmg
    [macos-x86_64-debug-symbols]=macOS-Intel-dSYMs.tar.xz
    [macos-x86_64-plugin-dev]=macOS-Intel-Libraries.tar.xz
    [ubuntu-24.04-x86_64]=Ubuntu-24.04-x86_64.deb
    [ubuntu-24.04-x86_64-debug-symbols]=Ubuntu-24.04-x86_64-dbsym.ddeb
    [ubuntu-24.04-x86_64-sources]=Ubuntu-24.04-x86_64-Sources.tar.gz
    [ubuntu-26.04-x86_64]=Ubuntu-26.04-x86_64.deb
    [ubuntu-26.04-x86_64-debug-symbols]=Ubuntu-26.04-x86_64-dbsym.ddeb
    [windows-x64]=Windows-x64.zip
    [windows-x64-installer]=Windows-x64-Installer.exe
    [windows-x64-debug-symbols]=Windows-x64-PDBs.zip
    [windows-x64-plugin-dev]=Windows-x64-Libraries.zip
    [windows-arm64]=Windows-ARM64.zip
    [windows-arm64-debug-symbols]=Windows-ARM64-PDBs.zip
    [windows-arm64-plugin-dev]=Windows-ARM64-Libraries.zip
  )

  local platform_glob="(macos|windows|ubuntu-*)"
  local arch_glob="(arm64|x86_64|x64)"
  local type_glob="(debug-symbols|dev|sources|installer|plugin-dev)"
  local extension_glob="(dmg|tar.xz|zip|exe|deb|ddeb)"

  : "${ARTIFACT_PATTERN:="obs-studio-@${platform_glob}-@${arch_glob}-*?(-@${type_glob}).@${extension_glob}"}"

  local glob_output
  glob_output="$(compgen -G "${PWD}/${ARTIFACT_PATTERN}" | sort --version-sort)"

  local platform
  local output_name
  local file_name
  local -a release_files=()
  local regex
  while read -r file; do
    file_name="$(basename "${file}")"

    regex="obs-studio-${platform_glob}-${arch_glob}-[^-]+(-${type_glob})?\.${extension_glob}$"

    if [[ "${file}" =~ ${regex} ]]; then
      platform="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"

      if [[ -n "${BASH_REMATCH[4]}" ]]; then
        platform+="-${BASH_REMATCH[4]}"
      fi

      output_name="OBS-Studio-${RELEASE_VERSION}-${platform_suffixes["${platform}"]}"

      release_files+=("${output_name}")

      mv "${file}" "${PWD}/${output_name}"
    else
      echo "::warning::File name '${file_name}' does not have a supported OBS Studio artifact name."
      continue
    fi
  done <<< "${glob_output}"

  {
    if (( ${#release_files[@]} )); then
      local json_string
      json_string="$(jq --compact-output --monochrome-output --raw-input '
        .,inputs | split(" ")
      ' <<< "${release_files[@]}")"

      echo "has-release-files=true"
      echo "release-files=${json_string}"
    else
      echo "has-releaese-files=false"
      echo "release-files=[]"
    fi
  } >> "${GITHUB_OUTPUT}"
}

rename-assets
