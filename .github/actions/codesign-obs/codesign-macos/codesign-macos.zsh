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

codesign-disk-image() {
  codesign --sign ${CODESIGN_IDENT} ${DISK_IMAGE}
}

notarize-disk-image() {
  if ! [[ -n "${CODESIGN_IDENT}" \
       && -n "${CODESIGN_TEAM}" \
       && -n "${NOTARIZATION_USER}" \
       && -n "${NOTARIZATION_PASS}" ]] \
  {
    print '::error::Notarization requires Apple ID and application password.'
    return 1
  }

  print '::group::Notarize Disk Image'
  local storage_identifier
  storage_identifier="$(print -- "${RANDOM}" | shasum | head --bytes=32)"
  print "::add-mask::${storage_identifier}"

  xcrun notarytool store-credentials ${storage_identifier} \
    --apple-id ${NOTARIZATION_USER} \
    --team-id ${CODESIGN_TEAM} \
    --password ${NOTARIZATION_PASS}

  xcrun notarytool submit ${DISK_IMAGE} --keychain-profile ${storage_identifier} --wait

  xcrun stapler staple ${DISK_IMAGE}

  print '::endgroup::'
}

codesign-macos() {
  if [[ ! -r ${DISK_IMAGE} ]] {
    print "::error::No macOS disk image found at '${DISK_IMAGE}'."
    return 1
  }

  codesign-disk-image

  if [[ "${RUN_NOTARIZATION:-false}" == 'true' ]] {
    notarize-disk-image
  }

  print "path=${DISK_IMAGE}" >> ${GITHUB_OUTPUT}
}



codesign-macos
