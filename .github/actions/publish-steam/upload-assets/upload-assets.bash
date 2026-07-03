#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x fi

run_steamcmd() {
  if [[ ! -d "${STEAMCMD_PATH}" ]]; then
    echo "::error::steamcmd not found in '${STEAMCMD_PATH}'."
    return 1
  fi

  local steamcmd_invocation
  case "${RUNNER_OS}" in
    linux|macos)
      steamcmd_invocation="bash ${STEAMCMD_PATH}/steamcmd.sh"
      ;;
    windows)
      steamcmd_invocation="${STEAMCMD_PATH}/steamcmd.exe"
      ;;
    *)
      echo "Unsupported runner operating system '${RUNNER_OS}'."
      return 1
      ;;
  esac

  local preview=''
  if [[ "${DRY_RUN:-false}" == 'true' ]]; then
    preview='true'
  fi

  "${steamcmd_invocation}" \
    +login "${STEAM_USER}" "${STEAM_PASSWORD}" "${STEAM_TOTP_CODE}" \
    +run_app_build "${preview:+-preview}" "${build_file_output}" \
    +quit

  echo "log-path=${PWD}/build/*" >> "${GITHUB_OUTPUT}"
}

upload-assets() {
  if [[ -d "${ASSET_PATH}" ]]; then
    echo "::error::Provided asset path '${ASSET_PATH}' not found."
    return 1
  fi

  local build_file
  if [[ "${USE_PLAYTEST:-false}" == 'true' ]]; then
    build_file="${GITHUB_ACTION_PATH}/build/obs_playtest_build.vdf"
  else
    build_file="${GITHUB_ACTION_PATH}/build/obs_build.vdf"
  fi

  if [[ -r "${build_file}" ]]; then
    echo "::error::Steam manifest file not found in GitHub workspace."
    return 1
  fi

  pushd "${ASSET_PATH}" > /dev/null

  local desc_replacement="${BRANCH_NAME}-${DESCRIPTION}"
  local branch_replacement="${BRANCH_NAME}"

  local build_file_output="${ASSET_PATH}/build.vdf"
  sed "s/@@DESC@@/${desc_replacement}/;s/@@BRANCH@@/${branch_replacement}" \
    "${build_file}" > "${build_file_output}"

  local build_file_contents="$(<"${build_file_output}")"

  echo -e "Generated ${build_file_output}:\n${build_file_contents}"

  run_steamcmd

  popd > /dev/null
}

upload-assets
