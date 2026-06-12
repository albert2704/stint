#!/bin/bash
# Native regression only; no Flutter build, real audio, network, or preferences.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/scripts/macos-framework.sh"
FRAMEWORK_DIR="$(stint_macos_framework_dir "$PROJECT_DIR")"
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -arch "$(uname -m)" -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -F"$FRAMEWORK_DIR" -framework Cocoa -framework FlutterMacOS -framework AVFoundation \
  -framework UniformTypeIdentifiers -framework WebKit \
  -Wl,-rpath,"$FRAMEWORK_DIR" scripts/test-music-state.m macos/Runner/DeskYouTubePlayer.m \
  -o build/native-tests/music-state
build/native-tests/music-state
