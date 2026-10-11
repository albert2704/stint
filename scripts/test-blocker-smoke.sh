#!/bin/bash
# Opt-in desktop integration. Briefly shows only our temporary fixture and
# restores the previous frontmost app. The fixture exits itself after 12 seconds.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
source "$PROJECT_DIR/scripts/macos-framework.sh"
FRAMEWORK_DIR="$(stint_macos_framework_dir "$PROJECT_DIR")"
PROBE_DIR="$PROJECT_DIR/build/native-tests/BlockerProbe.app"
FIXTURE_DIR="$PROBE_DIR/Contents/Resources/BlockerFixture.app"
mkdir -p "$PROBE_DIR/Contents/MacOS" "$PROBE_DIR/Contents/Frameworks" "$FIXTURE_DIR/Contents/MacOS"
rsync -a --delete "$FRAMEWORK_DIR/FlutterMacOS.framework" "$PROBE_DIR/Contents/Frameworks/"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -fmodules -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -DSTINT_BLOCKER_FIXTURE -framework Cocoa \
  scripts/test-blocker-smoke.m -o "$FIXTURE_DIR/Contents/MacOS/BlockerFixture"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -fmodules -fmodules-cache-path=build/native-module-cache -mmacosx-version-min=12.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -F"$FRAMEWORK_DIR" \
  -framework Cocoa -framework FlutterMacOS -framework UniformTypeIdentifiers \
  -Wl,-rpath,@executable_path/../Frameworks scripts/test-blocker-smoke.m macos/Runner/StintWebsiteBlocker.m macos/ProxyBlocker/StintLocalProxy.m macos/HostsBlocker/StintBlockerPolicy.m macos/HostsBlocker/StintHostsFile.m -o "$PROBE_DIR/Contents/MacOS/BlockerProbe"
python3 - "$PROBE_DIR" "$FIXTURE_DIR" <<'PY'
import plistlib, pathlib, sys
for folder, executable, identifier in ((sys.argv[1], 'BlockerProbe', 'io.github.albert2704.stint.blocker-probe'), (sys.argv[2], 'BlockerFixture', 'io.github.albert2704.stint.blocker-fixture')):
    data = dict(CFBundleExecutable=executable, CFBundleIdentifier=identifier, CFBundleName=executable, CFBundlePackageType='APPL', CFBundleVersion='1', NSPrincipalClass='NSApplication', LSMinimumSystemVersion='12.0')
    if executable == 'BlockerProbe': data['LSUIElement'] = True
    with (pathlib.Path(folder)/'Contents'/'Info.plist').open('wb') as handle: plistlib.dump(data, handle)
PY
codesign --force --sign - "$FIXTURE_DIR"
codesign --force --sign - "$PROBE_DIR/Contents/Frameworks/FlutterMacOS.framework"
codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$PROBE_DIR"
codesign --verify --deep --strict "$PROBE_DIR"
"$PROBE_DIR/Contents/MacOS/BlockerProbe"
