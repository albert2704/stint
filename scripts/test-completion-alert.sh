#!/bin/bash
# Native regression checks only; does not invoke Flutter or play audio.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/scripts/macos-framework.sh"
FRAMEWORK_DIR="$(stint_macos_framework_dir "$PROJECT_DIR")"
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -arch "$(uname -m)" -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -F"$FRAMEWORK_DIR" -framework Cocoa -framework Carbon -framework QuartzCore -framework CoreText -framework FlutterMacOS -framework UserNotifications -framework AVFoundation \
  -Wl,-rpath,"$FRAMEWORK_DIR" scripts/test-completion-alert.m macos/Runner/DeskAlertSound.m macos/Runner/DeskCompletionBanner.m macos/Runner/DeskKeymap.m -o build/native-tests/completion-alert
build/native-tests/completion-alert
