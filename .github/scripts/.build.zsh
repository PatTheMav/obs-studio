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

  if (( ${+CI} || _loglevel > 1)) {
    log_status "CCache Statistics"
    ccache -s -v
  }

  if (( ${+CI} )) unset NSUnbufferedIO

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

build() {
  if (( ! ${+SCRIPT_HOME} )) typeset -g SCRIPT_HOME=${ZSH_ARGZERO:A:h}
  local target_os=${${(s:-:)ZSH_ARGZERO:t:r}[2]}
  local target="${target_os}-${CPUTYPE}"
  local project_root=${SCRIPT_HOME:A:h:h}
  local buildspec_file="${project_root}/buildspec.json"

  fpath=("${SCRIPT_HOME}/utils.zsh" ${fpath})
  autoload -Uz log_info log_status log_error log_output set_loglevel check_${target_os} setup_${target_os} setup_ccache

  typeset -g -a skips=()
  local -i _verbosity=1
  local -r _version='1.0.0'
  local -r -a _valid_targets=(
    macos-x86_64
    macos-arm64
  )
  local -r -a _valid_configs=(Debug RelWithDebInfo Release MinSizeRel)
  if [[ ${target_os} == 'macos' ]] {
    local generator='Xcode'
    local -r -a _valid_generators=(Xcode Ninja 'Unix Makefiles')
  } else {
    local generator='Ninja'
    local -r -a _valid_generators=(Ninja 'Unix Makefiles')
  }
  local -i _print_config=0
  local -i _ci_release=0
  local -r _usage="
Usage: %B${functrace[1]%:*}%b <option> [<options>]

%BOptions%b:

%F{yellow} Build configuration options%f
 -----------------------------------------------------------------------------
  %B-t | --target%b                     Specify target - default: %B%F{green}${target_os}-${CPUTYPE}%f%b
  %B-c | --config%b                     Build configuration - default: %B%F{green}RelWithDebInfo%f%b
  %B-s | --codesign%b                   Enable codesigning (macOS only)
  %B--generator%b                       Specify build system to generate - default: %B%F{green}${generator}%f%b
                                    Available generators:
                                      - Ninja (Default on Linux)
                                      - Unix Makefiles
                                      - Xcode (Default on macOS)
  %B--print-config%b                    Print composed cmake configuration parameters

%F{yellow} Output options%f
 -----------------------------------------------------------------------------
  %B-q | --quiet%b                      Quiet (error output only)
  %B-v | --verbose%b                    Verbose (more detailed output)
  %B--skip-[all|build|deps|unpack]%b    Skip all|building OBS|checking for dependencies|unpacking dependencies
  %B--debug%b                           Debug (very detailed and added output)

%F{yellow} General options%f
 -----------------------------------------------------------------------------
  %B-h | --help%b                       Print this usage help
  %B-V | --version%b                    Print script version information"

  local -a args
  while (( # )) {
    case ${1} {
      -t|--target|-c|--config|--generator)
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
      -q|--quiet) (( _verbosity -= 1 )) || true; shift ;;
      -v|--verbose) (( _verbosity += 1 )); shift ;;
      -h|--help) log_output ${_usage}; exit 0 ;;
      -V|--version) print -Pr "${_version}"; exit 0 ;;
      --debug) _verbosity=3; shift ;;
      --generator)
        if (( ! ${_valid_generators[(Ie)${2}]} )) {
          log_error "Invalid value %B${2}%b for option %B${1}%b"
          log_output ${_usage}
          exit 2
        }
        generator=${2}
        shift 2
        ;;
      --print-config) _print_config=1; skips+=(unpack deps); shift ;;
      --ci-release) _ci_release=1; shift ;;
      --skip-*)
        local _skip="${${(s:-:)1}[-1]}"
        local _check=(all deps unpack build)
        (( ${_check[(Ie)${_skip}]} )) || log_warning "Invalid skip mode %B${_skip}%b supplied"
        skips+=(${_skip})
        shift
        ;;
      *) log_error "Unknown option: %B${1}%b"; log_output ${_usage}; exit 2 ;;
    }
  }

  set -- ${(@)args}
  set_loglevel ${_verbosity}

  check_${target_os}
  setup_ccache
  setup_${target_os}

  read -r product_name <<< \
    "$(jq -r '.name' ${project_root}/buildspec.json)"

  if (( ! (${skips[(Ie)all]} + ${skips[(Ie)build]}) )) {
    local -a cmake_args=(
      -DQT_VERSION:STRING=${QT_VERSION}
      -DENABLE_BROWSER:BOOL=ON
      -DENABLE_VLC:BOOL=ON
    )

    if (( ${+CI} )) cmake_args+=(-DOBS_BUILD_NUMBER:STRING=${GITHUB_RUN_ID:-1})
    if (( _ci_release )) cmake_args+=(-DENABLE_RELEASE_BUILD:BOOL=ON)

    if (( ${+TWITCH_CLIENTID} + ${+TWITCH_HASH} > 1 )) {
      cmake_args+=(
        -DTWITCH_CLIENTID:STRING="${TWITCH_CLIENTID}"
        -DTWITCH_HASH:STRING="${TWITCH_HASH}"
      )
    }

    if (( ${+RESTREAM_CLIENTID} + ${+RESTREAM_HASH} > 1 )) {
      cmake_args+=(
        -DRESTREAM_CLIENTID:STRING="${RESTREAM_CLIENTID}"
        -DRESTREAM_HASH:STRING="${RESTREAM_HASH}"
      )
    }

    if (( ${+YOUTUBE_CLIENTID} + ${+YOUTUBE_CLIENTID_HASH} + ${+YOUTUBE_SECRET} + ${+YOUTUBE_SECRET_HASH} > 3 )) {
      cmake_args+=(
        -DYOUTUBE_CLIENTID:STRING="${YOUTUBE_CLIENTID}"
        -DYOUTUBE_CLIENTID_HASH:STRING="${YOUTUBE_CLIENTID_HASH}"
        -DYOUTUBE_SECRET:STRING="${YOUTUBE_SECRET}"
        -DYOUTUBE_SECRET_HASH:STRING="${YOUTUBE_SECRET_HASH}"
      )
    }

    if (( _loglevel == 0 )) cmake_args+=(-Wno_deprecated -Wno-dev --log-level=ERROR)
    if (( _loglevel > 2 )) cmake_args+=(--debug-output)

    local num_procs
    case ${target} {
      macos-*)
        cmake_args+=(
          -DCEF_ROOT_DIR:PATH="${project_root:h}/obs-build-dependencies/cef_binary_${CEF_VERSION}_${target//-/_}"
          -DCMAKE_PREFIX_PATH:PATH="${project_root:h}/obs-build-dependencies/obs-deps-${OBS_DEPS_VERSION}-${target##*-}"
          -DVLC_PATH:PATH="${project_root:h}/obs-build-dependencies/vlc-${VLC_VERSION}"
          -DCMAKE_OSX_ARCHITECTURES:STRING=${${target##*-}//universal/x86_64;arm64}
          -DCMAKE_OSX_DEPLOYMENT_TARGET:STRING=${DEPLOYMENT_TARGET:-11.0}
          -DCMAKE_INSTALL_PREFIX:PATH=$(pwd)/build_${target##*-}/install
        )

        if (( _ci_release )) cmake_args+=(-DENABLE_SPARKLE=ON)

        if (( ${+CODESIGN} )) {
          read_codesign

          if [[ -z ${CODESIGN_IDENT} ]] {
            autoload -Uz read_codesign && read_codesign_team

            if [[ ${CODESIGN_TEAM} ]] cmake_args+=(-DOBS_CODESIGN_TEAM:STRING=${CODESIGN_TEAM})
          } else {
            cmake_args+=(-DOBS_CODESIGN_IDENTITY:STRING="${CODESIGN_IDENT}")
          }
        } else {
          cmake_args+=(-DOBS_CODESIGN_IDENTITY:STRING="-")
        }
        num_procs=$(( $(sysctl -n hw.ncpu) + 1 ))
        ;;
    }

    if (( _print_config )) { log_output "CMake configuration: ${cmake_args}"; exit 0 }

    log_info 'Configuring obs-studio...'
    log_debug "Attempting to configure obs-studio with CMake arguments: ${cmake_args}"
    cmake -S ${project_root} --preset=${target} -G ${generator} ${cmake_args}

    log_info 'Building obs...'
    local -a cmake_args=()
    if (( _loglevel > 1 )) cmake_args+=(--verbose)
    if [[ ${generator} == 'Unix Makefiles' ]] {
      cmake_args+=(--parallel ${num_procs})
    } else {
      cmake_args+=(--parallel)
    }

    if [[ ${generator} == 'Xcode' ]] {
      local -a xcbeautify_opts=()
      if (( _loglevel == 0 )) xcbeautify_opts+=(--quiet)
      if (( ${+CI} )) export NSUnbufferedIO=YES
      cmake --build build_${target##*-} --config ${BUILD_CONFIG:-RelWithDebInfo} ${cmake_args} 2>&1 | xcbeautify ${xcbeautify_opts}
    } else {
      cmake --build build_${target##*-} --config ${BUILD_CONFIG:-RelWithDebInfo} ${cmake_args}
    }
  }
  popd
}

build ${@}
