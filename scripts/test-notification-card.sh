#!/bin/bash
# Headless production card regression checks; no AppKit windows or real notifications.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -arch "$(uname -m)" -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework Cocoa -framework QuartzCore scripts/test-notification-card.m \
  -o build/native-tests/notification-card
build/native-tests/notification-card
