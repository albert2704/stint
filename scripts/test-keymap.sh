#!/bin/bash
# Production shortcut logic with fake registration/events, no windows or real hotkeys.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/scripts/macos-framework.sh"
FRAMEWORK_DIR="$(stint_macos_framework_dir "$PROJECT_DIR")"
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -arch "$(uname -m)" -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -F"$FRAMEWORK_DIR" -framework Cocoa -framework Carbon -framework FlutterMacOS \
  -Wl,-rpath,"$FRAMEWORK_DIR" scripts/test-keymap.m -o build/native-tests/keymap
build/native-tests/keymap
