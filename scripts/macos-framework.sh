#!/bin/bash
# Locate a cached Flutter macOS framework without invoking Flutter or downloading.
# Source this file and call stint_macos_framework_dir "$PROJECT_DIR", or run it.

_stint_framework_directory() {
  local stint_candidate="$1"
  if [ -d "$stint_candidate/FlutterMacOS.framework" ]; then
    (cd "$stint_candidate" && pwd -P)
    return 0
  fi
  return 1
}

_stint_framework_in_sdk() {
  local stint_sdk="$1" stint_engine stint_slice
  [ -n "$stint_sdk" ] || return 1
  # Flutter's universal macOS engine is commonly cached as darwin-x64, even on
  # Apple Silicon. Also accept a native-architecture cache if the SDK provides it.
  for stint_engine in darwin-x64 darwin-arm64; do
    for stint_slice in macos-arm64_x86_64 "macos-$(uname -m)"; do
      if _stint_framework_directory "$stint_sdk/bin/cache/artifacts/engine/$stint_engine/FlutterMacOS.xcframework/$stint_slice"; then
        return 0
      fi
    done
  done
  return 1
}

_stint_flutter_sdk_on_path() {
  local stint_executable stint_link stint_links=0
  stint_executable="$(type -P flutter)" || return 1
  # Resolve relative and chained links, including Homebrew's bin/flutter link.
  # macOS readlink has no portable -f option.
  while [ -L "$stint_executable" ]; do
    stint_links=$((stint_links + 1))
    [ "$stint_links" -le 40 ] || return 1
    stint_link="$(readlink "$stint_executable")" || return 1
    case "$stint_link" in
      /*) stint_executable="$stint_link" ;;
      *) stint_executable="$(dirname "$stint_executable")/$stint_link" ;;
    esac
  done
  [ -x "$stint_executable" ] || return 1
  (cd "$(dirname "$stint_executable")/.." && pwd -P)
}

stint_macos_framework_dir() {
  local stint_project_dir="$1" stint_path_sdk
  if [ -n "${STINT_FLUTTER_FRAMEWORK_DIR:-}" ]; then
    if _stint_framework_directory "$STINT_FLUTTER_FRAMEWORK_DIR"; then
      return 0
    fi
    printf '%s\n' 'STINT_FLUTTER_FRAMEWORK_DIR must name a directory containing FlutterMacOS.framework.' >&2
    return 1
  fi
  if _stint_framework_directory "$stint_project_dir/build/local/frameworks"; then
    return 0
  fi
  if _stint_framework_in_sdk "$stint_project_dir/.tooling/flutter"; then
    return 0
  fi
  if _stint_framework_in_sdk "${FLUTTER_ROOT:-}"; then
    return 0
  fi
  if stint_path_sdk="$(_stint_flutter_sdk_on_path)" && _stint_framework_in_sdk "$stint_path_sdk"; then
    return 0
  fi
  printf '%s\n' \
    'FlutterMacOS.framework was not found.' \
    'Install Flutter and add its bin directory to PATH, then run:' \
    '  bash scripts/flutter.sh precache --macos' \
    'Or set FLUTTER_ROOT to your Flutter SDK, or STINT_FLUTTER_FRAMEWORK_DIR to the directory containing FlutterMacOS.framework.' >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  stint_macos_framework_dir "$(cd "$(dirname "$0")/.." && pwd)"
fi
