#!/bin/bash
# Build, sign, package, notarize and staple the Salvum fork of ClaudeUsageBar.
# arm64-only (Apple Silicon). Run from the `app/` directory.

set -e

APP_NAME="ClaudeUsageBar"
DMG_NAME="ClaudeUsageBar-Salvum"
DEVELOPER_ID="Developer ID Application: Salvum (HLH2929Z66)"
NOTARY_PROFILE="salvum-notarytool"

# Pin Xcode 16.4 (SDK 15.5) — Xcode 26 / SDK 26 causes an NSPopover positioning
# regression on macOS 26 (the popover is mispositioned off-screen).
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer

APP_PATH="build/${APP_NAME}.app"

echo "→ Clean build dir"
rm -rf build
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "→ Stage bundle"
cp Info.plist "$APP_PATH/Contents/"
if [ -f ClaudeUsageBar.icns ]; then
  cp ClaudeUsageBar.icns "$APP_PATH/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ClaudeUsageBar" "$APP_PATH/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ClaudeUsageBar" "$APP_PATH/Contents/Info.plist"
fi

echo "→ Compile arm64 (SDK $(xcrun --sdk macosx --show-sdk-version))"
xcrun swiftc -parse-as-library -O \
  -o "$APP_PATH/Contents/MacOS/${APP_NAME}" \
  ClaudeUsageBar.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework WebKit \
  -target arm64-apple-macos12.0

echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"
chmod 755 "$APP_PATH/Contents/MacOS/${APP_NAME}"

echo "→ Strip xattrs"
xattr -cr "$APP_PATH"

echo "→ Sign .app with $DEVELOPER_ID"
codesign --force --deep --options runtime --sign "$DEVELOPER_ID" "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH"

echo "→ Build DMG"
TMP_DIR="dmg_temp"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cp -R "$APP_PATH" "$TMP_DIR/"
xattr -cr "$TMP_DIR/${APP_NAME}.app"
ln -s /Applications "$TMP_DIR/Applications"

rm -f "${DMG_NAME}.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$TMP_DIR" -ov -format UDZO "${DMG_NAME}.dmg" >/dev/null
rm -rf "$TMP_DIR"

echo "→ Sign DMG"
codesign --force --sign "$DEVELOPER_ID" "${DMG_NAME}.dmg"

echo "→ Submit to Apple notary service (~2-5 min)…"
xcrun notarytool submit "${DMG_NAME}.dmg" --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ Staple notarization ticket"
xcrun stapler staple "${DMG_NAME}.dmg"

echo "→ Verify Gatekeeper acceptance"
spctl -a -t open --context context:primary-signature -v "${DMG_NAME}.dmg" || true

echo ""
echo "✅ Ready: ${DMG_NAME}.dmg"
echo "   Send via AirDrop / iMessage / Mail."
