#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and package CCAS.app into a ZIP and a DMG.
#
# Environment:
#   SIGNING_IDENTITY        Required for signing. e.g.
#                           "Developer ID Application: LuYang Li (RHVTXHK83V)"
#   APPLE_ID                Apple ID email (required for notarization)
#   APPLE_APP_PASSWORD      App-specific password (required for notarization)
#   APPLE_TEAM_ID           Developer Team ID (required for notarization)
#   SKIP_NOTARIZE           Set to "1" to sign but skip notarization.
#
# Behavior:
#   - If SIGNING_IDENTITY is unset, the .app is built but left unsigned and no
#     archives are produced (CI / local sanity build).
#   - If signing creds are set but notarization creds are missing, the script
#     signs the app and builds ZIP/DMG, but does not submit to Apple.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS="$ROOT_DIR/Sources/CCASApp/CCAS.entitlements"

# Stage the bundle outside the project tree. If the project lives inside an
# iCloud / Dropbox / OneDrive synced folder, the file provider keeps re-adding
# com.apple.FinderInfo / fileprovider xattrs that codesign refuses to sign.
STAGE_DIR="/tmp/ccas"
APP_DIR="$STAGE_DIR/CCAS.app"
DMG_STAGE_DIR="$STAGE_DIR/dmg-stage"

cd "$ROOT_DIR"

# Don't swallow build_app.sh output — SwiftPM compile diagnostics go to
# stdout, so redirecting it to /dev/null hides the actual error when a build
# fails in CI. Keep the full build log visible.
"$ROOT_DIR/scripts/build_app.sh"

BUILT_APP="$DIST_DIR/CCAS.app"
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_APP/Contents/Info.plist")"
MIN_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$BUILT_APP/Contents/Info.plist")"
BASENAME="CCAS-${MARKETING_VERSION}"
STAGED_ZIP="$STAGE_DIR/${BASENAME}.zip"
STAGED_DMG="$STAGE_DIR/${BASENAME}.dmg"
ZIP_PATH="$DIST_DIR/${BASENAME}.zip"
DMG_PATH="$DIST_DIR/${BASENAME}.dmg"
APPCAST_ITEM="$DIST_DIR/appcast-item.xml"

if [ -z "${SIGNING_IDENTITY:-}" ]; then
    echo "SIGNING_IDENTITY not set; produced unsigned $BUILT_APP" >&2
    exit 0
fi

echo "==> Staging bundle at $APP_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$BUILT_APP" "$APP_DIR"
xattr -cr "$APP_DIR"

echo "==> Signing $APP_DIR with identity: $SIGNING_IDENTITY"
codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

needs_notarize=1
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    needs_notarize=0
fi
if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
    needs_notarize=0
    echo "Notarization credentials not fully set; will package without notarization." >&2
fi

submit_for_notarization() {
    local target="$1"
    echo "==> Submitting $target to notarytool"
    xcrun notarytool submit "$target" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
}

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$STAGED_ZIP"

if [ "$needs_notarize" = "1" ]; then
    submit_for_notarization "$STAGED_ZIP"
    echo "==> Stapling $APP_DIR"
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"

    # Re-zip so the archive contains the stapled bundle.
    rm -f "$STAGED_ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$STAGED_ZIP"
fi

echo "==> Building DMG"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

hdiutil create \
    -volname "CCAS ${MARKETING_VERSION}" \
    -srcfolder "$DMG_STAGE_DIR" \
    -ov -format UDZO \
    "$STAGED_DMG"
rm -rf "$DMG_STAGE_DIR"

codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$STAGED_DMG"

if [ "$needs_notarize" = "1" ]; then
    submit_for_notarization "$STAGED_DMG"
    xcrun stapler staple "$STAGED_DMG"
    xcrun stapler validate "$STAGED_DMG"
fi

echo "==> Copying artifacts to $DIST_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH"
cp "$STAGED_ZIP" "$ZIP_PATH"
cp "$STAGED_DMG" "$DMG_PATH"

# Build a Sparkle appcast <item> snippet. CI consumes APPCAST_ITEM and merges
# it into the published appcast.xml on gh-pages. Inline the GFM-rendered HTML
# notes (per DealChangelog.md) instead of pointing at a remote URL so Sparkle
# does not load GitHub's full release page inside its WebView.
if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    GITHUB_REPOSITORY="bones7456/ccas"
fi
SPARKLE_TAG="${SPARKLE_TAG:-v${MARKETING_VERSION}}"
ZIP_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${SPARKLE_TAG}/${BASENAME}.zip"
FULL_NOTES_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${SPARKLE_TAG}"
ZIP_LENGTH="$(stat -f%z "$ZIP_PATH")"

SIGN_UPDATE="$(find "$ROOT_DIR/.build/artifacts" -type f -name sign_update -not -path '*old_dsa*' -print -quit)"
if [ -z "$SIGN_UPDATE" ]; then
    echo "error: sign_update not found under .build/artifacts; run 'swift package resolve' first" >&2
    exit 1
fi

SIGN_ARGS=()
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SIGN_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi

echo "==> Signing ZIP with EdDSA"
ED_SIG_ATTRS="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" "$ZIP_PATH")"
# sign_update prints e.g. ` sparkle:edSignature="..." length="..."` (note leading space)
ED_SIG_ATTRS="${ED_SIG_ATTRS# }"

if [ -n "${SPARKLE_RELEASE_NOTES_FILE:-}" ] && [ -s "${SPARKLE_RELEASE_NOTES_FILE}" ]; then
    NOTES_HTML="$(cat "$SPARKLE_RELEASE_NOTES_FILE")"
else
    NOTES_HTML="<p>See <a href=\"${FULL_NOTES_URL}\">release notes on GitHub</a>.</p>"
fi

PUB_DATE="$(LC_TIME=en_US date -u "+%a, %d %b %Y %H:%M:%S +0000")"

cat > "$APPCAST_ITEM" <<EOF
<item xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <title>Version ${MARKETING_VERSION}</title>
    <pubDate>${PUB_DATE}</pubDate>
    <sparkle:version>${BUILD_VERSION}</sparkle:version>
    <sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
    <sparkle:fullReleaseNotesLink>${FULL_NOTES_URL}</sparkle:fullReleaseNotesLink>
    <description><![CDATA[
${NOTES_HTML}
    ]]></description>
    <enclosure url="${ZIP_URL}" ${ED_SIG_ATTRS} type="application/octet-stream" />
</item>
EOF

echo "==> Artifacts:"
echo "    $ZIP_PATH"
echo "    $DMG_PATH"
echo "    $APPCAST_ITEM"
