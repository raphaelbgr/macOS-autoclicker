#!/bin/bash
# make-dmg.sh — Package the signed/notarized .app into a pretty DMG
#
# Uses Apple's dmgpkg + a drag-to-Applications layout (no third-party
# create-dmg dependency — pure hdiutil + AppleScript for the icon layout).
#
# Usage:
#   ./scripts/make-dmg.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="macOS AutoClicker"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App not built. Run ./scripts/build.sh (and ./scripts/sign-notarize.sh) first."
    exit 1
fi

# Read version for the DMG volume name.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
VOL_NAME="$APP_NAME $VERSION"

echo "📦 Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"

# Stage a temporary folder with the .app + an Applications symlink,
# then hdiutil it into a DMG. This is the simplest reliable approach
# without needing create-dmg.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "✅ DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"
echo ""
echo "If signed + notarized, users can drag to Applications and run without Gatekeeper warnings."
