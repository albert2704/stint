#!/bin/bash
# Development packaging using Apple's Command Line Tools. Standard releases use Xcode.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [ "$(uname -m)" != arm64 ]; then
  echo "This local development helper currently targets Apple Silicon. Use flutter build macos with Xcode on Intel."
  exit 1
fi
STINT_VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml)"
STINT_BUILD_NUMBER="$(sed -n 's/^version:[[:space:]]*[^+]*+\([0-9][0-9]*\)[[:space:]]*$/\1/p' pubspec.yaml)"
STINT_BUILD_NUMBER="${STINT_BUILD_NUMBER:-1}"
case "$STINT_VERSION" in
  ''|*[!0-9.]*) echo 'Expected a numeric x.y.z version in pubspec.yaml.' >&2; exit 1 ;;
esac
bash scripts/flutter.sh pub get
bash scripts/flutter.sh precache --macos --no-ios --no-android --no-web --no-linux --no-windows --no-fuchsia
bash scripts/flutter.sh assemble -dTargetPlatform=darwin -dBuildMode=debug -dDarwinArchs=arm64 -dTargetFile=lib/main.dart --output=build/local/frameworks debug_macos_bundle_flutter_assets
APP_DIR="${STINT_APP_DIR:-$PROJECT_DIR/build/local/Stint.app}"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
rsync -a --delete build/local/frameworks/FlutterMacOS.framework "$APP_DIR/Contents/Frameworks/"
rsync -a --delete build/local/frameworks/App.framework "$APP_DIR/Contents/Frameworks/"
SDK_DIR="$(xcrun --sdk macosx --show-sdk-path)"
# Link in an empty staging directory first. Replace only the generated executable
# directory after linking succeeds, so an explicit rebuild retains no stale host.
STINT_EXECUTABLE_DIR="$(mktemp -d "$PROJECT_DIR/build/local/stint-executable.XXXXXX")"
trap 'rm -rf "$STINT_EXECUTABLE_DIR"' EXIT
xcrun clang -arch arm64 -fobjc-arc -fmodules -fmodules-cache-path=build/local/clang-module-cache -mmacosx-version-min=12.0 -isysroot "$SDK_DIR" \
  -Fbuild/local/frameworks -framework Cocoa -framework Carbon -framework QuartzCore -framework CoreText -framework FlutterMacOS -framework UserNotifications -framework AVFoundation -framework UniformTypeIdentifiers -framework WebKit \
  -Wl,-rpath,@executable_path/../Frameworks scripts/local_macos_runner.m macos/Runner/StintMenuBar.m macos/Runner/StintAlertSound.m macos/Runner/StintCompletionBanner.m macos/Runner/StintKeymap.m macos/Runner/StintMusic.m macos/Runner/StintYouTubePlayer.m macos/Runner/StintBlocker.m macos/Runner/StintWebsiteBlocker.m macos/ProxyBlocker/StintLocalProxy.m macos/HostsBlocker/StintBlockerPolicy.m macos/HostsBlocker/StintHostsFile.m -o "$STINT_EXECUTABLE_DIR/Stint"
rsync -a --delete "$STINT_EXECUTABLE_DIR/" "$APP_DIR/Contents/MacOS/"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Stint</string>
<key>CFBundleIdentifier</key><string>io.github.albert2704.stint</string>
<key>CFBundleName</key><string>Stint</string>
<key>CFBundleDisplayName</key><string>Stint</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$STINT_VERSION</string>
<key>CFBundleVersion</key><string>$STINT_BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Use the supplied macOS icon sizes; do not regenerate the retired icon.
STINT_ASSET_CATALOG="$PROJECT_DIR/macos/Runner/Assets.xcassets"
ICONSET="$PROJECT_DIR/build/local/StintIcon.iconset"
mkdir -p "$ICONSET"
for side in 16 32 128 256 512; do
  cp "$STINT_ASSET_CATALOG/AppIcon.appiconset/app_icon_${side}.png" "$ICONSET/icon_${side}x${side}.png"
  double=$((side * 2))
  cp "$STINT_ASSET_CATALOG/AppIcon.appiconset/app_icon_${double}.png" "$ICONSET/icon_${side}x${side}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$STINT_ASSET_CATALOG/StatusTemplate.imageset/StatusTemplate.png" "$STINT_ASSET_CATALOG/StatusTemplate.imageset/StatusTemplate@2x.png" "$APP_DIR/Contents/Resources/"
# Remove only the obsolete bundled extension when rebuilding an older preview.
rm -rf "$APP_DIR/Contents/Resources/stint-blocker"
rm -rf "$APP_DIR/Contents/Library/SystemExtensions/io.github.albert2704.stint.networkfilter.systemextension"
bash scripts/build-hosts-helper.sh "$APP_DIR" arm64
codesign --force --sign - "$APP_DIR/Contents/Frameworks/FlutterMacOS.framework"
codesign --force --sign - "$APP_DIR/Contents/Frameworks/App.framework"
codesign --force --sign - --entitlements macos/Runner/DebugProfile.entitlements "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
