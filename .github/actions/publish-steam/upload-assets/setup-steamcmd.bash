#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

: "${CI:?}"
if [[ -n "${RUNNER_DEBUG:-}" ]]; then set -x; fi

setup-steamcmd() {
  local -A download_urls=(
    [windows]='https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    [macos]='https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'
    [linux]='https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
  )

  local download_url="${download_urls["${RUNNER_OS,,*}"]}"
  local file_name="$(basename "${download_url}")"

  curl \
    --silent \
    --location \
    --output-dir "${RUNNER_TEMP}" \
    --remote-name "${download_url}"

  mkdir -p "${RUNNER_TEMP}/steamcmd"
  pushd "${RUNNER_TEMP}/steamcmd" > /dev/null

  case "${RUNNER_OS,,*}" in
  windows)
    unzip -q "${RUNNER_TEMP}/${file_name}"

    (
      set +o errexit
      "${PWD}/steamcmd.exe" +quit
      set -o errexit

      if (( $? != 0 && $? != 7  )); then
        echo '::error::Unexpected exit code for first run of steamcmd on Windows.'
        return 1
      fi
    )
    ;;
  macos)
    tar --extract --bzip --file "${RUNNER_TEMP}/${file_name}"

    bash "${PWD}/steamcmd.sh" +quit
    ;;
  linux)
    tar --extract --bzip --file "${RUNNER_TEMP}/${file_name}"

    sudo apt-get install --yes --no-install-recommends lib32gcc-s1

    bash "${PWD}/steamcmd.sh" +quit
    ;;
  *)
    echo "::error::Unsupported runner operating system '${RUNNER_OS}'."
    return 1
    ;;
  esac

  echo "path=${RUNNER_TEMP}/steamcmd" > "${GITHUB_OUTPUT}"
  popd > /dev/null
}

setup-steamcmd
