#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
APP_NAME="CoderSwitch"
DMG_NAME="CoderSwitch.dmg"

mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"
xcodegen generate
xcodebuild -scheme CoderSwitch -configuration Release build

APP_PATH="$(xcodebuild -scheme CoderSwitch -configuration Release -showBuildSettings \
  | awk -F ' = ' '/TARGET_BUILD_DIR/ { dir=$2 } /FULL_PRODUCT_NAME/ { name=$2 } END { print dir "/" name }')"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Could not find built app at $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$BUILD_DIR/staging"
rm -rf "$STAGING_DIR" "$BUILD_DIR/$DMG_NAME"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$STAGING_DIR/$APP_NAME.app"
fi

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$BUILD_DIR/$DMG_NAME"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$BUILD_DIR/$DMG_NAME"
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
  xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
fi

echo "$BUILD_DIR/$DMG_NAME"
