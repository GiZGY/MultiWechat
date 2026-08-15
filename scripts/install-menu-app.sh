#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/WxMulti/MultiWechat.app"
LEGACY_APP_DIR="$HOME/Applications/WxMulti/WxMultiMenu.app"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/multiwechat-install.XXXXXX")"
BUILD_APP="$BUILD_ROOT/MultiWechat.app"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

VERSION=0.1.0 CONFIGURATION=debug OUTPUT_APP="$BUILD_APP" "$ROOT_DIR/scripts/build-app.sh"

CURRENT_EXECUTABLE="$APP_DIR/Contents/MacOS/wxmulti-menu"
while IFS= read -r pid; do
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
done < <(pgrep -f "^${CURRENT_EXECUTABLE}$" || true)

mkdir -p "$(dirname "$APP_DIR")"
if [[ -d "$LEGACY_APP_DIR" && "$LEGACY_APP_DIR" != "$APP_DIR" ]]; then
  rm -rf "$LEGACY_APP_DIR"
fi
if [[ -e "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
ditto "$BUILD_APP" "$APP_DIR"
open "$APP_DIR"

echo "$APP_DIR"
