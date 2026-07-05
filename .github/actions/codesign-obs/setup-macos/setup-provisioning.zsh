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
if (( ${+RUNNER_DEBUG} )) setopt XTRACE

: ${CI:?}

setup-notarization() {
  if [[ -n "${PROVISIONING_PROFILE}" ]] {
    print 'have-provisioning-profile=true' >> ${GITHUB_OUTPUT}

    local -r profile_path="${RUNNER_TEMP}/build_profile.provisionprofile"
    base64 --decode --output=${profile_path} <<< "${PROVISIONING_PROFILE}"

    print '::group::Provisioning Profile Setup'
    mkdir -p "${HOME}/Library/MobileDevice/Provisioning Profiles"
    security cms \
      -D \
      -i ${profile_path} \
      -o ${RUNNER_TEMP}/build_profile.plist

    local uuid="$(plutil -extract UUID raw ${RUNNNER_TEMP}/build_profile.plist)"
    print "::addmask::${uuid}"

    local team_id="$(plutil -extract TeamIdentifier.0 raw -expect string ${RUNNER_TEMP}/build_profile.plist)"
    print "::addmask::${team_id}"

    if [[ ${team_id} != ${CODESIGN_TEAM:-} ]] {
      print '::notice::Code Signing team in provisioning profile does not match certificate.'
    }

    cp ${profile_path} "${HOME}/Library/MobileDevice/Provisioning Profiles/${uuid}.provisionprofile"
    print "profile-uuid=${uuid}" >> ${GITHUB_OUTPUT}
    print '::endgroup::'
  } else {
    print "profile-uuid=null" >> ${GITHUB_OUTPUT}
    print 'have-provisioning-profile=false' >> ${GITHUB_OUTPUT}
  }
}

setup-notarization
