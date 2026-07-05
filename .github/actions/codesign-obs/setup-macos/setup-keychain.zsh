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

setup-keychain() {
  if [[ -n "${SIGNING_IDENTITY}" && \
        -n "${SIGNING_CERT}" && \
        -n "${SIGNING_CERT_PASSWORD}" ]] \
  {
    print 'have-codesign-ident=true' >> ${GITHUB_OUTPUT}

    local certificate_path="${RUNNER_TEMP}/build_certificate.p12"
    local keychain_path="${RUNNER_TEMP}/app-signing.keychain-db"

    base64 --decode --output=${certificate_path} <<< "${SIGNING_CERT}"

    print '::group::Keychain setup'
    local keychain_password="$(print ${RANDOM} | shasum | head --bytes=32)"
    print "::addmask::${keychain_password}"

    security create-keychain -p ${keychain_password} ${keychain_path}
    security set-keychain-settings -lut 21600 ${keychain_path}
    security unlock-keychain -p ${keychain_password} ${keychain_path}

    security import ${certificate_path} \
      -P ${SIGNING_CERT_PASSWORD}  \
      -A \
      -t cert \
      -f pkcs12 \
      -k ${keychain_path} \
      -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcrun

    security set-key-partition-list \
      -S 'apple-tool:,apple:' \
      -k ${keychain_password} \
      ${keychain_path} &> /dev/null

    security list-keychain \
      -d user \
      -s ${keychain_path} \
      login-keychain
    print '::endgroup::'

    local team_id="${${SIGNING_IDENTITY##* }//(\(|\))/}"
    print "::addmask::${team_id}"

    print "codesign-ident=${SIGNING_IDENTITY}" >> ${GITHUB_OUTPUT}
    print "keychain-password=${keychain_password}" >> ${GITHUB_OUTPUT}
    print "codesign-team=${team_id}" >> ${GITHUB_OUTPUT}
  } else {
    print 'haveCodesign-ident=false' >> ${GITHUB_OUTPUT}
    print "codesign-ident=null" >> ${GITHUB_OUTPUT}
    print "keychain-password=null" >> ${GITHUB_OUTPUT}
    print "codesign-team=null" >> ${GITHUB_OUTPUT}
  }
}

setup-keychain
