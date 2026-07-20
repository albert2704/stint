#!/bin/bash
# Compile and embed only; never install the helper or edit the real hosts file.
set -euo pipefail
STINT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STINT_APP="${1:?Pass the destination Stint.app}"
STINT_ARCHS="${2:-$(uname -m)}"
STINT_RESOURCES="$STINT_APP/Contents/Resources/WebsiteBlocker"
mkdir -p "$STINT_RESOURCES" "$STINT_ROOT/build/hosts-module-cache"
rm -rf "$STINT_APP/Contents/Library/SystemExtensions/io.github.albert2704.stint.networkfilter.systemextension"
STINT_ARCH_FLAGS=()
for stint_arch in $STINT_ARCHS; do
  case "$stint_arch" in arm64|x86_64) STINT_ARCH_FLAGS+=(-arch "$stint_arch");; *) echo 'Unsupported helper architecture.' >&2; exit 1;; esac
done
xcrun clang "${STINT_ARCH_FLAGS[@]}" -Wall -Wextra -Werror -O2 -fobjc-arc -fmodules \
  -fmodules-cache-path="$STINT_ROOT/build/hosts-module-cache" -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -framework Foundation -framework Security -framework SystemConfiguration \
  "$STINT_ROOT/macos/HostsBlocker/StintHostsHelper.m" "$STINT_ROOT/macos/HostsBlocker/StintHostsFile.m" \
  "$STINT_ROOT/macos/HostsBlocker/StintBlockerPolicy.m" "$STINT_ROOT/macos/ProxyBlocker/StintProxyPreferences.m" -o "$STINT_RESOURCES/StintHostsHelper"
cp "$STINT_ROOT/macos/HostsBlocker/Install Website Blocker.command" "$STINT_ROOT/macos/HostsBlocker/Remove Website Blocker.command" "$STINT_RESOURCES/"
chmod 755 "$STINT_RESOURCES/"*.command
codesign --force --sign - "$STINT_RESOURCES/StintHostsHelper"
codesign --verify --strict "$STINT_RESOURCES/StintHostsHelper"
