#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -DSTINT_PROXY_TESTING=1 -framework Foundation -framework SystemConfiguration \
  scripts/test-proxy-preferences.m macos/ProxyBlocker/StintProxyPreferences.m \
  -o build/native-tests/proxy-preferences
# This executable uses fake preferences only, plus an isolated journal fixture.
build/native-tests/proxy-preferences
