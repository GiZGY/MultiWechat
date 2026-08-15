#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_APP="${OUTPUT_APP:-$ROOT_DIR/dist/MultiWechat.app}"
UNIVERSAL="${UNIVERSAL:-0}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-io.github.gizgy.MultiWechat}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

BUILD_ARGS=(build --package-path "$ROOT_DIR" -c "$CONFIGURATION")
if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift "${BUILD_ARGS[@]}"
BIN_DIR="$(swift "${BUILD_ARGS[@]}" --show-bin-path)"

if [[ ! -x "$BIN_DIR/wxmulti-menu" || ! -x "$BIN_DIR/wxmulti" ]]; then
  echo "缺少构建产物: $BIN_DIR" >&2
  exit 1
fi

if [[ -e "$OUTPUT_APP" ]]; then
  rm -rf "$OUTPUT_APP"
fi

CONTENTS_DIR="$OUTPUT_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
ditto "$BIN_DIR/wxmulti-menu" "$MACOS_DIR/wxmulti-menu"
ditto "$BIN_DIR/wxmulti" "$MACOS_DIR/wxmulti"
ditto "$ROOT_DIR/assets/WxMultiIcon.icns" "$RESOURCES_DIR/WxMultiIcon.icns"
ditto "$ROOT_DIR/assets/WxMultiStatusTemplate.png" "$RESOURCES_DIR/WxMultiStatusTemplate.png"

INFO_PLIST="$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -create xml1 "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string wxmulti-menu" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_IDENTIFIER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string MultiWechat" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string MultiWechat" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string WxMultiIcon" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © 2026 ZGY. All rights reserved." "$INFO_PLIST"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$OUTPUT_APP"
else
  /usr/bin/codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$OUTPUT_APP"
fi

touch "$OUTPUT_APP"
echo "$OUTPUT_APP"
