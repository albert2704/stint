#!/bin/bash
# Build a universal AOT preview with Xcode, then package and verify it.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'Full Xcode is required. The GitHub Package macOS workflow can build this for you.' >&2
  exit 1
fi
VERSION="$(sed -n 's/^version: \([^+ ]*\).*/\1/p' pubspec.yaml)"
case "$VERSION" in
  ''|*[!0-9.]*) echo 'Expected a numeric x.y.z version in pubspec.yaml.' >&2; exit 1 ;;
esac
OUTPUT="$PROJECT_DIR/build/distribution"
STAGE="$PROJECT_DIR/build/package-stage"
APP="$STAGE/Stint.app"
mkdir -p "$OUTPUT"
# This staging directory contains generated release files only.
rm -rf "$STAGE"
mkdir -p "$STAGE"
bash scripts/flutter.sh pub get
bash scripts/flutter.sh precache --macos --no-ios --no-android --no-web --no-linux --no-windows --no-fuchsia
bash scripts/flutter.sh build macos --release --config-only
# Configure through Flutter, then build directly so CI cannot replace the
# checked-in sandbox entitlements with Flutter's development CI override.
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath "$PROJECT_DIR/build/macos" \
  -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= COMPILER_INDEX_STORE_ENABLE=NO build

ditto "$PROJECT_DIR/build/macos/Build/Products/Release/Stint.app" "$APP"
# An incremental Xcode build can retain a resource removed from the project.
rm -rf "$APP/Contents/Resources/stint-blocker"
rm -f "$OUTPUT/Stint-$VERSION-browser-extension.zip"
# Ship original and bundled dependency licenses inside the application.
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES"
cp LICENSE "$LICENSES/Stint-MIT.txt"
cp THIRD_PARTY_NOTICES.md "$LICENSES/THIRD_PARTY_NOTICES.md"
cp assets/fonts/HankenGrotesk/OFL.txt "$LICENSES/HankenGrotesk-OFL.txt"
cp assets/fonts/MartianMono/OFL.txt "$LICENSES/MartianMono-OFL.txt"
STINT_SDK="$(sed -n 's/^FLUTTER_ROOT=//p' macos/Flutter/ephemeral/Flutter-Generated.xcconfig | head -1)"
cp "$STINT_SDK/LICENSE" "$LICENSES/Flutter-LICENSE.txt"
cp "$STINT_SDK/bin/cache/artifacts/engine/darwin-x64-release/LICENSE.artifacts.md" "$LICENSES/Flutter-Engine-NOTICES.md"
cp "$STINT_SDK/bin/cache/pkg/sky_engine/LICENSE" "$LICENSES/Flutter-Engine-LICENSE.txt"

# Integrity-only ad hoc signing. The ordinary local proxy needs no Network Extension entitlement.
while IFS= read -r -d '' framework; do
  codesign --force --sign - "$framework"
done < <(find "$APP/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
for binary in "$APP/Contents/MacOS/Stint" \
  "$APP/Contents/Frameworks/App.framework/App" \
  "$APP/Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS" \
  "$APP/Contents/Resources/WebsiteBlocker/StintHostsHelper"; do
  lipo "$binary" -verify_arch arm64 x86_64
done
if find "$APP" -name kernel_blob.bin -print | grep -q .; then
  echo 'Refusing to package a debug Dart kernel.' >&2
  exit 1
fi
codesign --display --entitlements :- "$APP" > "$OUTPUT/entitlements.plist"
python3 - "$OUTPUT/entitlements.plist" "$APP" "$VERSION" <<'PY'
import pathlib, plistlib, sys
entitlements = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
assert entitlements.get('com.apple.security.app-sandbox') is True
assert entitlements.get('com.apple.security.network.client') is True
assert entitlements.get('com.apple.security.network.server') is True
assert not entitlements.get('com.apple.security.automation.apple-events')
assert not entitlements.get('com.apple.security.temporary-exception.apple-events')
assert not entitlements.get('com.apple.developer.system-extension.install')
assert not entitlements.get('com.apple.developer.networking.networkextension')
assert entitlements.get('com.apple.security.temporary-exception.files.home-relative-path.read-write') == ['/Library/Application Support/Stint Website Blocker/']
assert not entitlements.get('com.apple.security.get-task-allow')
assert not entitlements.get('com.apple.security.cs.allow-jit')
assert not (pathlib.Path(sys.argv[2])/'Contents/Resources/stint-blocker').exists()
info = plistlib.loads((pathlib.Path(sys.argv[2])/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'io.github.albert2704.stint'
assert not info.get('NSAppleEventsUsageDescription')
assert not info.get('NSSystemExtensionUsageDescription')
assert info['CFBundleExecutable'] == 'Stint'
assert info['CFBundleShortVersionString'] == sys.argv[3]
assert info['LSMinimumSystemVersion'] == '12.0'
resources = pathlib.Path(sys.argv[2])/'Contents/Resources/WebsiteBlocker'
for name in ('StintHostsHelper', 'Install Website Blocker.command', 'Remove Website Blocker.command'):
    assert (resources/name).is_file()
assert not (pathlib.Path(sys.argv[2])/'Contents/Library/SystemExtensions/io.github.albert2704.stint.networkfilter.systemextension').exists()
PY
if [ "${STINT_PACKAGE_SMOKE_TEST:-0}" = 1 ]; then
  python3 scripts/smoke-release-macos.py "$APP" "$OUTPUT/bootstrap.log"
fi
cat > "$STAGE/Install Stint.txt" <<'TEXT'
Stint for macOS 12 or later (Apple Silicon and Intel)

Drag Stint.app to Applications, then open it from Applications.
Quit an older copy of Stint before replacing it.

Check the release notes for its signing and notarization status.
macOS may block the first launch of an unnotarized preview. Only if you trust this download,
follow Apple's Open Anyway guidance in System Settings > Privacy & Security:
https://support.apple.com/en-us/102445

Downloads and source: https://github.com/albert2704/stint
Install guide: https://github.com/albert2704/stint/blob/main/docs/install.md
Licenses are in Stint.app/Contents/Resources/Licenses.
Website blocking: Settings > Block distractions > Set up website blocker.
Double-click the setup command revealed in Finder. It opens in Terminal and asks
for administrator approval once to install the free helper.
No Apple Developer subscription, network extension or browser extension is needed.
During focus, macOS HTTP/HTTPS traffic uses Stint's local proxy. Browsers stay open.
HTTPS stays encrypted. Apps that ignore system proxies are outside its protection.
The helper restores your previous proxy settings after focus. Existing proxy setups
are unsupported. Setup upgrades the older hosts helper if it is installed.
Use Remove helper in Stint to uninstall it. See the setup guide for recovery.
Setup guide: https://github.com/albert2704/stint/blob/main/docs/blocking.md
TEXT
ZIP="$OUTPUT/Stint-$VERSION-macos-universal.zip"
DMG="$OUTPUT/Stint-$VERSION-macos-universal.dmg"
# ZIP includes the app and install guide, without a nested staging directory.
(cd "$STAGE" && ditto -c -k --sequesterRsrc . "$ZIP")
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Stint $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
printf 'Packaged Stint %s in %s\n' "$VERSION" "$OUTPUT"
