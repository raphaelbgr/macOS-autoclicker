#!/bin/bash
# build.sh — Release build of macOS OCR AutoClicker
#
# Produces a Release-config .app in DerivedData and copies it to dist/.
# Does NOT sign or notarize — see sign-notarize.sh for that.
#
# Usage:
#   ./scripts/build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$ROOT_DIR/macOS AutoClicker.xcodeproj"
SCHEME="macOS AutoClicker"
CONFIGURATION="Release"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="macOS AutoClicker"

echo "🔨 Building $APP_NAME ($CONFIGURATION)…"
cd "$ROOT_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$ROOT_DIR/build" \
    -destination 'generic/platform=macOS' \
    build

# Locate the built .app and copy to dist/.
BUILT_APP="$ROOT_DIR/build/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "❌ Build succeeded but .app not found at: $BUILT_APP"
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$DIST_DIR/"

echo ""
echo "✅ Built: $DIST_DIR/$APP_NAME.app"
echo "   Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DIST_DIR/$APP_NAME.app/Contents/Info.plist")"
echo "   Version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST_DIR/$APP_NAME.app/Contents/Info.plist")"
echo ""
echo "Next: ./scripts/sign-notarize.sh (requires Developer ID) — or open dist/$APP_NAME.app directly to test unsigned."
