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
: "${preview:=}"
: "${mode:=}"
: "${code:=}"
: "${branch:=}"
: "${description:=}"
: "${user_name:="${STEAM_USER}"}"
: "${password:="${STEAM_PASSWORD}"}"

args=()

while true; do
  case "${1}" in
    --mode) mode="${2}"; shift 2 ;;
    --code) code="${2}"; shift 2 ;;
    --branch) branch_name="${2}"; shift 2 ;;
    --desc) description="${2}"; shift 2 ;;
    --user) user_name="${2}"; shift 2 ;;
    --pass) password="${2}"; shift 2 ;;
    --preview) preview=1; shift ;;
    --) shift; args+=(${@}); break ;;
    *) echo "Unsupported option: '${1}'"; exit 2 ;;
  esac
done

pushd steam
echo "::group::Prepare Steam build script"

# The description in Steamworks for the build will be
# "github_<branch>-<tag/short hash>", e.g. "github_nightly-gaa73de952"
case "${mode}" in
  release)
    build_file='build.vdf'
    sed "s/@@DESC@@/${branch_name}-${description}/;s/@@BRANCH@@/${branch_name}/" \
      ${root_dir}/.github/scripts/utils.steam/obs_build.vdf > "${build_file}"
    echo "Generated ${build_file}:\n$(<"${build_file}")"
    ;;
  playtest)
    build_file='build_playtest.vdf'
    sed "s/@@DESC@@/${{branch_name}-${description}/;s/@@BRANCH@@/${branch_name}/" \
    ${root_dir}/.github/scripts/utils.steam/obs_playtest_build.vdf > "${build_file}"
    echo "Generated ${build_file}:\n$(<"${build_file}")"
    ;;
  *) echo "Unsupported mode provided: ${mode}."; exit 2 ;;
esac
echo "::endgroup::"

echo "::group::Upload to Steam"
steamcmd \
  +login "${user_name}" "${password}" "${code}" \
  +run_app_build "${preview:+-preview}" "${root_dir}/${build_file}" \
  +quit
echo "::endgroup::"
