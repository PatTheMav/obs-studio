#!/usr/bin/env zsh

builtin emulate -L zsh
setopt ERR_EXIT
setopt ERR_RETURN
setopt EXTENDED_GLOB
setopt FUNCTION_ARGZERO
setopt NO_AUTO_PUSHD
setopt NO_PUSHD_IGNORE_DUPS
setopt NO_UNSET
setopt PIPE_FAIL
setopt PUSHD_SILENT
setopt WARN_CREATE_GLOBAL
setopt WARN_NESTED_VAR

: ${CI:?}
if (( ${+RUNNER_DEBUG} )) setopt XTRACE

setup-macos() {
  case ${LINTER_COMMAND:-} {
    clang-format)
      brew trust obsproject/tools/clang-format@22
      brew install --quiet obsproject/tools/clang-format@22
      ;;
    gersemi)
      brew install --quiet gersemi
      ;;
    swift-format)
      brew install --quiet swift-format
      ;;
    xmllint) ;;
    zizmor)
      brew install --quiet zizmor
      ;;
    *)
      return 1
  }
}

setup-macos
