#!/bin/bash
# sign-notarize.sh — Codesign with Developer ID + submit to Apple notarytool
#
# Requires (set via env vars or GitHub Actions secrets):
#   MAC_SIGNING_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID               your developer account email
#   APPLE_TEAM_ID          your 10-char team ID
#   APPLE_APP_PASSWORD     app-specific password from appleid.apple.com
#
# Hardened runtime + runtime options match the entitlements file already
# declared in the Xcode project (sandbox OFF, Apple Events ON).
#
# Usage:
#   MAC_SIGNING_IDENTITY="Developer ID Application: …" \
#   APPLE_ID="you@example.com" APPLE_TEAM_ID="ABCDE12345" \
#   APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#   ./scripts/sign-notarize.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="macOS AutoClicker"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/macOS AutoClicker/App/MacOSAutoClicker.entitlements"

# Required env vars.
for var in MAC_SIGNING_IDENTITY APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Missing required env var: $var"
        echo ""
        echo "Local dev build? Skip this script and open dist/$APP_NAME.app directly."
        echo "CI release? Add the four secrets above to the workflow."
        exit 2
    fi
done

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App not built. Run ./scripts/build.sh first."
    exit 1
fi

echo "🔐 Codesigning with: $MAC_SIGNING_IDENTITY"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$MAC_SIGNING_IDENTITY" \
    --timestamp \
    "$APP_PATH"

echo "✅ Signed. Verifying…"
codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | head -5
echo "   spctl assessment:"
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 | head -3 || true

echo ""
echo "📤 Submitting to notarytool (this can take 5–30 min)…"
# Zip first — notarytool prefers a zip for .app bundles.
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id    "$APPLE_ID" \
    --team-id     "$APPLE_TEAM_ID" \
    --password    "$APPLE_APP_PASSWORD" \
    --wait

echo ""
echo "📌 Stapling the ticket…"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo ""
echo "🧹 Cleaning zip…"
rm -f "$ZIP_PATH"

echo ""
echo "✅ Notarized + stapled: $APP_PATH"
echo "   Distribute via ./scripts/make-dmg.sh"
