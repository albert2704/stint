#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native-tests
xcrun clang -Wall -Wextra -Werror -fobjc-arc -fmodules \
  -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -framework Cocoa -framework Security -framework SystemConfiguration scripts/test-hosts-blocker.m \
  macos/HostsBlocker/StintBlockerPolicy.m macos/HostsBlocker/StintHostsFile.m macos/ProxyBlocker/StintProxyPreferences.m macos/ProxyBlocker/StintLocalProxy.m \
  -o build/native-tests/hosts-blocker
# Intel linkers do not automatically add the signature used by copy validation.
codesign --force --sign - build/native-tests/hosts-blocker
build/native-tests/hosts-blocker
