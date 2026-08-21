#!/bin/bash
#
# Builds QuickSnap and wraps the binary in a proper .app bundle.
#
# A menu-bar app needs to be a real .app (with an Info.plist and a bundle id)
# for macOS to remember its Screen Recording permission and to hide the Dock
# icon reliably. `swift build` only produces a bare executable, so this script
# assembles the bundle around it and ad-hoc code-signs it.
#
set -euo pipefail

APP_NAME="QuickSnap"
BUNDLE_ID="dev.nihir.quicksnap"
VERSION="0.1.0"
CONFIG="release"

cd "$(dirname "$0")"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/${APP_NAME}.app"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- LSUIElement = menu-bar-only app, no Dock icon. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Sign with a stable identity if one is provided. Set QUICKSNAP_SIGN_IDENTITY to
# the name of a self-signed "Code Signing" certificate to keep macOS permissions
# (e.g. Screen Recording) across rebuilds; otherwise fall back to ad-hoc, which
# changes signature every build and forces macOS to re-ask for permission.
SIGN_IDENTITY="${QUICKSNAP_SIGN_IDENTITY:--}"
echo "▸ Code-signing (identity: ${SIGN_IDENTITY})…"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "✓ Built ${APP_DIR}"
echo "  Run it with:  open \"${APP_DIR}\""
