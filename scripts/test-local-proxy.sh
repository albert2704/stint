#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -DSTINT_PROXY_TESTING=1 -framework Foundation \
  scripts/test-local-proxy.m macos/HostsBlocker/StintBlockerPolicy.m \
  macos/ProxyBlocker/StintLocalProxy.m -o build/native-tests/local-proxy
build/native-tests/local-proxy
