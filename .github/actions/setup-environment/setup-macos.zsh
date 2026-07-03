#!/usr/bin/env zsh

builtin emulate -L zsh
setopt PUSHD_SILENT
setopt EXTENDED_GLOB
setopt ERR_EXIT
setopt ERR_RETURN
setopt NO_UNSET
setopt PIPE_FAIL
setopt NO_AUTO_PUSHD
setopt NO_PUSHD_IGNORE_DUPS
setopt NO_GLOB_SUBST
setopt WARN_CREATE_GLOBAL
setopt WARN_NESTED_VAR

: ${CI:?}
if (( ${+RUNNER_DEBUG} )) setopt XTRACE

switch-xcode-version() {
  print '::group::Switch Xcode version'
  if [[ -n ${XCODE_VERSION:-} ]] {
    if [[ ${XCODE_VERSION} == <->##.<-> ]] {
      if [[ -d /Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer ]] {
        sudo xcode-select --switch /Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer
      } else {
        print "::error::Xcode version ${XCODE_VERSION} not found on runner."
        return 1
      }
    } else {
      print "::error::Provided invalid version value ${XCODE_VERSION}."
      return 1
    }
  } else {
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  }
  print '::endgroup::'
}

setup-metadata() {
  if [[ -d ${PWD}/.git && -r ${PWD}/CMakePresets.json ]] {
    local output
    local version
    local base_url
    local checksum

    output="$(jq -r '
      .configurePresets[]
      | select(.name=="dependencies")
      | .vendor["obsproject.com/obs-studio"].tools.sparkle
      | {version, baseUrl, hash}
      | join(" ")
    ' ${PWD}/CMakePresets.json)"

    read -r version base_url checksum <<< "${output}"

    {
      if [[ -n "${version}" && -n ${base_url} && -n ${checksum} ]] {
        print "sparkle-version=${version}"
        print "sparkle-url=${base_url}"
        print "sparkle-checksum=${checksum}"

      } else {
        print 'sparkle-version=null'
        print 'sparkle-url=null'
        print 'sparkle-checksum=null'
      }
    } >> ${GITHUB_OUTPUT}
  }
}

setup-macos() {
  switch-xcode-version
  function() {
    if [[ -n ${TARGET} ]] {
      local -A arch_names=(
        [arm64]=Apple
        [x86_64]=Intel
      )
      print "cpu-name=${arch_names[${TARGET}]}"
    }
  }  >> ${GITHUB_OUTPUT}

  local xcode_cas_path="${HOME}/Library/Developer/Xcode/DerivedData/CompilationCache.noindex"
  if [[ ! -d ${xcode_cas_path} ]] {
    mkdir -p ${xcode_cas_path}
  }

  print "xcode-cas-path=${xcode_cas_path}" >> ${GITHUB_OUTPUT}

  setup-metadata
}

setup-macos
