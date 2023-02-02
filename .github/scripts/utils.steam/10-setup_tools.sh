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

root_dir="$(pwd)"

if ! (( ${#SEVENZIP_ARCHIVE} && ${#SEVENZIP_HASH} )); then
  echo "Either 'SEVENZIP_ARCHIVE' or 'SEVENZIP_HASH' not set - skipping 7-Zip installations"
else
  mkdir -p "${root_dir}/tools/7zip" && pushd "${root_dir}/tools/7ip"

  curl --show-error --silent -O https://www.7-zip.org/a/${SEVENZIP_ARCHIVE}

  _downloaded_checksum="$(sha256sum "${SEVENZIP_ARCHIVE}" | cut -d ' ' -f 1)"
  if [[ "${SEVENZIP_HASH}" != "${_downloaded_checksum}" ]]; then
    echo "Checksum of downloaded ${SEVENZIP_ARCHIVE} does not match specification."
    echo "Expected : ${SEVENZIP_HASH}"
    echo "Actual   : ${_downloaded_checksum}"
    exit 2
  fi

  tar -xJf ${SEVENZIP_ARCHIVE}
  echo "${root_dir}/tools/7zip" >> $GITHUB_PATH

  popd
fi

_required_packages=()

if ! type jq &> /dev/null; then
  _required_packages+=(jq)
fi

if ! type curl &> /dev/null; then
  _required_packages+=(curl)
fi

sudo apt-get -y install "${_required_packages[@]}"
