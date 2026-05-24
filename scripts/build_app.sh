#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/CCAS.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCE_SOURCE_DIR="$ROOT_DIR/Sources/CCASApp/Resources"
INFO_PLIST="$ROOT_DIR/Sources/CCASApp/Info.plist"
XCODE_PROJECT="$ROOT_DIR/CCAS.xcodeproj"
SCHEME="${SCHEME:-CCAS}"
CONFIGURATION="${CONFIGURATION:-Release}"

cd "$ROOT_DIR"

BUILD_SETTINGS_FILE="$(mktemp)"
trap 'rm -f "$BUILD_SETTINGS_FILE"' EXIT

xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings \
    > "$BUILD_SETTINGS_FILE"

build_setting() {
    local key="$1"
    awk -F' = ' -v key="$key" '
        $1 ~ "^[[:space:]]*" key "$" {
            print $2
            exit
        }
    ' "$BUILD_SETTINGS_FILE"
}

MARKETING_VERSION="${MARKETING_VERSION:-$(build_setting MARKETING_VERSION)}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(build_setting CURRENT_PROJECT_VERSION)}"
PRODUCT_BUNDLE_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-$(build_setting PRODUCT_BUNDLE_IDENTIFIER)}"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/CCAS" "$MACOS_DIR/CCAS"
chmod +x "$MACOS_DIR/CCAS"

if [ -d "$RESOURCE_SOURCE_DIR" ]; then
    cp -R "$RESOURCE_SOURCE_DIR/." "$RESOURCES_DIR/"
fi

# Embed Sparkle.framework. SwiftPM links against the XCFramework's binary but
# does not copy it into the .app — we have to do it ourselves so @rpath lookup
# at @executable_path/../Frameworks resolves at launch.
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SPARKLE_SRC="$(find "$ROOT_DIR/.build/artifacts" -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
if [ -z "$SPARKLE_SRC" ]; then
    echo "error: Sparkle.framework not found under .build/artifacts; run 'swift package resolve' first" >&2
    exit 1
fi
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/Sparkle.framework"

cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PRODUCT_BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CURRENT_PROJECT_VERSION" "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
