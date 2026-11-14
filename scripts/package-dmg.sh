#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/Lumakey.app"
DMG_PATH="${1:-$ROOT_DIR/dist/Lumakey.dmg}"
STAGE_DIR="$ROOT_DIR/.build/dmg-stage"

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: $APP_DIR not found. Run scripts/build-macos.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"
rm -rf "$STAGE_DIR" "$DMG_PATH" "${DMG_PATH}.sha256"
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/Lumakey.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Packaging $DMG_PATH"
hdiutil create -volname "Lumakey" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"

shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"
echo "Packaged $DMG_PATH ($(cat "${DMG_PATH}.sha256"))."
