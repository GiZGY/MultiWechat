#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/multiwechat-release.XXXXXX")"
APP_PATH="$WORK_DIR/MultiWechat.app"
DMG_PATH="$DIST_DIR/MultiWechat-${VERSION}.dmg"
ZIP_PATH="$DIST_DIR/MultiWechat-${VERSION}.zip"
CHECKSUM_PATH="$DIST_DIR/MultiWechat-${VERSION}-checksums.txt"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"

VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
CONFIGURATION=release \
UNIVERSAL=1 \
OUTPUT_APP="$APP_PATH" \
"$ROOT_DIR/scripts/build-app.sh"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
file "$APP_PATH/Contents/MacOS/wxmulti-menu" "$APP_PATH/Contents/MacOS/wxmulti"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

DMG_STAGE="$WORK_DIR/dmg"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/MultiWechat.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -quiet -volname MultiWechat -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"

if [[ "${CODESIGN_IDENTITY:--}" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
