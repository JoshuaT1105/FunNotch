#!/bin/bash
#
# Builds FunNotch.app without Xcode, using only the Command Line Tools.
#
#   ./build.sh              build for the host architecture
#   ./build.sh --universal  build a universal (arm64 + x86_64) binary
#   ./build.sh --run        build, then relaunch the app
#   ./build.sh --debug      build without optimisation
#   ./build.sh --package    also write dist/*.zip and a drag-to-Applications dmg
#
# Releasing to other people:
#
#   ./build.sh --universal --package \
#     --sign "Developer ID Application: Your Name (TEAMID)" \
#     --notarize funnotch-profile
#
# Without --sign the bundle is signed ad-hoc, which is fine on this Mac but
# makes Gatekeeper call it damaged on anyone else's. Ad-hoc signatures also
# change on every build, and macOS ties Automation and Accessibility grants to
# the signature — which is why those permission prompts keep coming back during
# development. A real Developer ID fixes both.
#
# --notarize takes the name of a keychain profile created once with:
#
#   xcrun notarytool store-credentials funnotch-profile \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FunNotch"
BUNDLE_ID="com.funnotch.FunNotch"
VERSION="1.1"
BUILD_NUMBER="4"
MIN_MACOS="14.0"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

DIST_DIR="dist"

UNIVERSAL=0
RUN_AFTER=0
PACKAGE=0
SIGN_IDENTITY=""
NOTARY_PROFILE=""
OPT_FLAGS="-O -whole-module-optimization"

while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --run) RUN_AFTER=1 ;;
    --debug) OPT_FLAGS="-Onone -g" ;;
    --package) PACKAGE=1 ;;
    --sign)
      shift
      [ $# -gt 0 ] || { echo "--sign needs an identity" >&2; exit 1; }
      SIGN_IDENTITY="$1"
      ;;
    --notarize)
      shift
      [ $# -gt 0 ] || { echo "--notarize needs a keychain profile name" >&2; exit 1; }
      NOTARY_PROFILE="$1"
      PACKAGE=1
      ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
  shift
done

if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "--notarize needs --sign too: Apple will not notarise an ad-hoc signature" >&2
  exit 1
fi

SOURCES=$(find Sources -name '*.swift' | sort)
if [ -z "$SOURCES" ]; then
  echo "no sources found" >&2
  exit 1
fi

FRAMEWORKS=(
  AppKit SwiftUI Combine Foundation
  ApplicationServices
  AVFoundation AudioToolbox CoreAudio CoreLocation CoreMedia CoreImage CoreGraphics
  CoreWLAN
  EventKit IOBluetooth IOKit Quartz QuartzCore ServiceManagement
  QuickLookThumbnailing UniformTypeIdentifiers UserNotifications Vision
)
FRAMEWORK_FLAGS=()
for fw in "${FRAMEWORKS[@]}"; do
  FRAMEWORK_FLAGS+=(-framework "$fw")
done

# Sparkle's public signing key. The matching private key is in the login
# Keychain ("Private key for signing Sparkle updates") and must be backed up:
# lose it and no existing install can ever be updated again.
SPARKLE_PUBLIC_KEY="Tt+/6ryqRjQqe9D+8b5a8d1q1Icgc+3zyOpA2d2z+t0="

# Sparkle powers in-app updates. Fetched rather than committed; see the script.
"$(dirname "$0")/Tools/fetch-sparkle.sh"
SPARKLE_DIR="$(cd "$(dirname "$0")" && pwd)/Vendor"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"

echo "==> Cleaning"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

compile_slice() {
  local arch="$1"
  local out="$2"
  echo "==> Compiling ($arch)"
  # shellcheck disable=SC2086
  xcrun swiftc \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    $OPT_FLAGS \
    -swift-version 5 \
    -parse-as-library \
    -module-name "$APP_NAME" \
    "${FRAMEWORK_FLAGS[@]}" \
    -F "$SPARKLE_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -o "$out" \
    $SOURCES
}

if [ "$UNIVERSAL" -eq 1 ]; then
  compile_slice arm64 "$BUILD_DIR/${APP_NAME}-arm64"
  compile_slice x86_64 "$BUILD_DIR/${APP_NAME}-x86_64"
  echo "==> Creating universal binary"
  lipo -create "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64" \
    -output "$MACOS_DIR/$APP_NAME"
  rm -f "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"
else
  compile_slice "$(uname -m)" "$MACOS_DIR/$APP_NAME"
fi

echo "==> Embedding Sparkle"
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
cp -R "$SPARKLE_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Fun Notch</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>

    <!-- Sparkle. The public key is the trust anchor: an update is installed
         only if it carries an EdDSA signature made with the matching private
         key, which lives in the developer's login Keychain and nowhere else.
         That check is what makes updates safe despite ad-hoc code signing. -->
    <!-- Served from the repo rather than funnotch.xyz on purpose. If the feed
         is unreachable every install silently stops updating, and the domain
         has already been suspended once by the registrar. GitHub is the more
         durable host for the one file that keeps everyone else current. -->
    <key>SUFeedURL</key>              <string>https://raw.githubusercontent.com/JoshuaT1105/FunNotch/main/appcast.xml</string>
    <key>SUPublicEDKey</key>          <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>

    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>

    <key>NSCameraUsageDescription</key>
    <string>The mirror shows a live preview of your camera inside the notch.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Your upcoming events are shown inside the notch.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Your upcoming events are shown inside the notch.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Your reminders are shown alongside calendar events inside the notch.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Your reminders are shown alongside calendar events inside the notch.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Fun Notch controls Music and Spotify to show and change what is playing.</string>
    <!-- Required: touching IOBluetooth without these keys is a hard TCC kill. -->
    <!-- Required: weather needs a rough location, and macOS also gates the
         Wi-Fi network name behind location access. -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Fun Notch uses your rough location for the weather widget and to read the current Wi-Fi network name.</string>
    <key>NSLocationUsageDescription</key>
    <string>Fun Notch uses your rough location for the weather widget and to read the current Wi-Fi network name.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Fun Notch shows your Bluetooth devices connecting and disconnecting in the notch.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Fun Notch shows your Bluetooth devices connecting and disconnecting in the notch.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Files you drop on the shelf are read from wherever you dragged them.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Files you drop on the shelf are read from wherever you dragged them.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Files you drop on the shelf are read from wherever you dragged them.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Building app icon"
if [ -f "Tools/MakeIcon.swift" ]; then
  ICON_BIN="$BUILD_DIR/makeicon"
  if [ ! -x "$ICON_BIN" ] || [ "Tools/MakeIcon.swift" -nt "$ICON_BIN" ]; then
    xcrun swiftc -O -target "$(uname -m)-apple-macos${MIN_MACOS}" \
      -framework AppKit -o "$ICON_BIN" Tools/MakeIcon.swift
  fi
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  "$ICON_BIN" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICONSET"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> Signing as $SIGN_IDENTITY"
  # --timestamp and the hardened runtime are both required for notarisation.
  codesign --force --deep --sign "$SIGN_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements FunNotch.entitlements \
    "$APP_DIR"
  codesign --verify --deep --strict --verbose=1 "$APP_DIR"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --deep --sign - \
    --options runtime \
    --entitlements FunNotch.entitlements \
    "$APP_DIR" 2>/dev/null \
    || codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Built $APP_DIR"

if [ "$PACKAGE" -eq 1 ]; then
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR/staging"

  ARCH_LABEL=$(lipo -archs "$MACOS_DIR/$APP_NAME" | tr ' ' '-')
  ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH_LABEL.zip"

  echo "==> Packaging $ZIP_PATH"
  # ditto rather than `zip`: it is the only one that keeps the bundle's
  # signature and resource forks intact, and notarytool rejects the rest.
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

  if [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Notarising (this waits on Apple, usually a few minutes)"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    # Staple the app, then rebuild the zip so the ticket travels with it.
    xcrun stapler staple "$APP_DIR"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
  fi

  cp -R "$APP_DIR" "$DIST_DIR/staging/"
  ln -s /Applications "$DIST_DIR/staging/Applications"
  if [ -f "INSTALL.txt" ]; then
    cp "INSTALL.txt" "$DIST_DIR/staging/Read Me First.txt"
  fi

  DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
  echo "==> Packaging $DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR/staging" \
    -ov -format UDZO "$DMG_PATH" >/dev/null

  if [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Notarising the disk image"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
  fi

  rm -rf "$DIST_DIR/staging"
  echo "==> Packaged:"
  ls -lh "$DIST_DIR"

  if [ -z "$SIGN_IDENTITY" ]; then
    echo
    echo "    Note: ad-hoc signed. Gatekeeper will call this damaged on any"
    echo "    other Mac; the recipient has to right-click > Open once. Pass"
    echo "    --sign and --notarize for a build that just opens."
  fi
fi

if [ "$RUN_AFTER" -eq 1 ]; then
  echo "==> Relaunching"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  open "$APP_DIR"
fi
