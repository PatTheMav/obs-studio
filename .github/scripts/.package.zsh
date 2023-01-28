#!/usr/bin/env zsh

builtin emulate -L zsh
setopt EXTENDED_GLOB
setopt PUSHD_SILENT
setopt ERR_EXIT
setopt ERR_RETURN
setopt NO_UNSET
setopt PIPE_FAIL
setopt NO_AUTO_PUSHD
setopt NO_PUSHD_IGNORE_DUPS
setopt FUNCTION_ARGZERO

## Enable for script debugging
#setopt WARN_CREATE_GLOBAL
#setopt WARN_NESTED_VAR
#setopt XTRACE

autoload -Uz is-at-least && if ! is-at-least 5.2; then
  print -u2 -PR "%F{1}${funcstack[1]##*/}:%f Running on Zsh version %B${ZSH_VERSION}%b, but Zsh %B5.2%b is the minimum supported version. Upgrade Zsh to fix this issue."
  exit 1
fi

TRAPEXIT() {
  local return_value=$?

  if (( ${+CI} )) {
    unset NSUnbufferedIO
  }

  return ${return_value}
}

TRAPZERR() {
  print -u2 -PR '%F{1}    ✖︎ script execution error%f'
  print -PR -e "
    Callstack:
    ${(j:\n     :)funcfiletrace}
  "
  exit 2
}

package() {
  if (( ! ${+SCRIPT_HOME} )) typeset -g SCRIPT_HOME=${ZSH_ARGZERO:A:h}
  local target_os=${${(s:-:)ZSH_ARGZERO:t:r}[2]}
  local target="${target_os}-${CPUTYPE}"
  local project_root=${SCRIPT_HOME:A:h:h}
  local buildspec_file="${project_root}/buildspec.json"

  fpath=("${SCRIPT_HOME}/utils.zsh" ${fpath})
  autoload -Uz set_loglevel log_info log_error log_output check_${target_os}

  local -i _verbosity=1
  local -r _version='1.0.0'
  local -r -a _valid_targets=(
    macos-x86_64
    macos-arm64
    linux-x86_64
    linux-aarch64
  )
  local -r -a _valid_configs=(Debug RelWithDebInfo Release MinSizeRel)
  local -i _skip_pack=0
  local -r _usage="
Usage: %B${functrace[1]%:*}%b <option> [<options>]

%BOptions%b:

%F{yellow} Package configuration options%f
 -----------------------------------------------------------------------------
  %B-t | --target%b                     Specify target - default: %B%F{green}${target_os}-${CPUTYPE}%f%b
  %B-c | --config%b                     Build configuration - default: %B%F{green}RelWithDebInfo%f%b
  %B-s | --codesign%b                   Enable codesigning (macOS only)
  %B-n | --notarize%b                   Enable notarization (macOS only)

%F{yellow} Output options%f
 -----------------------------------------------------------------------------
  %B-q | --quiet%b                      Quiet (error output only)
  %B-v | --verbose%b                    Verbose (more detailed output)
  %B--skip-pack%b %b                    Skip package creation (useful for notarization/codesigning)
  %B--debug%b                           Debug (very detailed and added output)

%F{yellow} General options%f
 -----------------------------------------------------------------------------
  %B-h | --help%b                       Print this usage help
  %B-V | --version%b                    Print script version information"

  local -a args
  while (( # )) {
    case ${1} {
      -t|--target|-c|--config)
        if (( # == 1 )) || [[ ${2:0:1} == '-' ]] {
          log_error "Missing value for option %B${1}%b"
          log_output ${_usage}
          exit 2
        }
        ;;
    }
    case ${1} {
      --)
        shift
        args+=($@)
        break
        ;;
      -t|--target)
        if (( ! ${_valid_targets[(Ie)${2}]} )) {
          log_error "Invalid value %B${2}%b for option %B${1}%b"
          log_output ${_usage}
          exit 2
        }
        target=${2}
        shift 2
        ;;
      -c|--config)
        if (( ! ${_valid_configs[(Ie)${2}]} )) {
          log_error "Invalid value %B${2}%b for option %B${1}%b"
          log_output ${_usage}
          exit 2
        }
        BUILD_CONFIG=${2}
        shift 2
        ;;
      -s|--codesign) CODESIGN=1; shift ;;
      -n|--notarize) NOTARIZE=1; shift ;;
      -q|--quiet) (( _verbosity -= 1 )) || true; shift ;;
      -v|--verbose) (( _verbosity += 1 )); shift ;;
      -h|--help) log_output ${_usage}; exit 0 ;;
      -V|--version) print -Pr "${_version}"; exit 0 ;;
      --skip-pack) _skip_pack=1; shift ;;
      --debug) _verbosity=3; shift ;;
      *) log_error "Unknown option: %B${1}%b"; log_output ${_usage}; exit 2 ;;
    }
  }

  set -- ${(@)args}
  set_loglevel ${_verbosity}

  check_${target_os}

  if [[ ${target_os} == 'macos' ]] {
    autoload -Uz read_codesign read_codesign_pass log_warning

    if (( ! _skip_pack )) {
      log_info "Creating macOS disk image..."
      log_warning "/!\\ CPack will use an AppleScript to create the disk image, this will lead to a Finder window opening to adjust window settings. /!\\"
      local -a cpack_args=()
      if (( _loglevel > 1 )) cpack_args+=(--verbose)

      pushd ${project_root}/build_${target##*-}
      cpack -C ${BUILD_CONFIG:-RelWithDebInfo} ${cpack_args}
      popd
    }

    disk_images=(${project_root}/build_${target##*-}/obs-studio-*.dmg(om))
    app_bundles=(${project_root}/build_${target##*-}/_CPack*/**/OBS.app(om))

    if (( ! ${#app_bundles} )) {
      log_error 'No OBS.app found. Check the CPack output for errors.'
      return 2
    }

    if (( ${#disk_images} > 0 )) {
      log_info "Codesigning macOS disk image"
      if (( ${+CODESIGN} )) read_codesign
      codesign --force --sign "${CODESIGN_IDENT:--}" "${disk_images[1]}"
    }

    if (( ${+CODESIGN} && ${+NOTARIZE} )) && (( ${#disk_images} )) {
      read_codesign_pass

      xcrun notarytool submit "${disk_images[1]}" --keychain-profile "OBS-Codesign-Password" --wait

      local -i _status=0

      xcrun stapler staple "${disk_images[1]}" || _status=1

      if (( _status )) {
        log_error "Notarization failed - use 'xcrun notarytool log <Submission ID>' to check for errors.'"
        return 2
      }
    }
  } elif [[ ${target_os} == 'linux' ]] {
    if (( ! _skip_pack )) {
      local -a cpack_args=()
      if (( _loglevel > 1 )) cpack_args+=(--verbose)

      pushd ${project_root}/build_${target##*-}
      cpack -C ${BUILD_CONFIG:-RelWithDebInfo} ${cpack_args}

      if (( ${+CI} )) {
        deb_package=(obs-studio-*.deb(om))
        deb_dbg_package=(obs-studio-*.ddeb(om))

        if (( ! ${#deb_package} )) {
          log_error 'No generated debian package found. Check the CPack output for errors.'
          return 2
        }

        local ubuntu_version=$(lsb_release -sr)
        mv ${deb_package[1]} ${${deb_package[1]}//-Linux.deb/-ubuntu-${ubuntu_version}-${target##*-}.deb}

        if (( ${#deb_dbg_package} )) mv ${deb_dbg_package[1]} ${${deb_dbg_package[1]}//-Linux-dbgsym.ddeb/-ubuntu-${ubuntu_version}-${target##*-}-dbgsym.ddeb}
      }

      popd
    }
  }
}

package ${@}
