#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/Lucent.app"
DMG_PATH="${1:-$ROOT_DIR/dist/Lucent.dmg}"
STAGE_DIR="${TMPDIR:-/tmp}/lucent-dmg-stage-$$"

if [[ ! -d "$APP_DIR" ]]; then
  echo "ERROR: $APP_DIR not found. Run scripts/build-macos.sh first." >&2
  exit 1
fi

mkdir -p "$(dirname "$DMG_PATH")"
rm -rf "$STAGE_DIR" "$DMG_PATH" "${DMG_PATH}.sha256"
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/Lucent.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Packaging $DMG_PATH"
hdiutil create -volname "Lucent" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"

DMG_SIGN_ID="${LUCENT_SIGN_IDENTITY:-}"
if [[ -z "$DMG_SIGN_ID" ]]; then
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  DMG_SIGN_ID=$(printf '%s\n' "$identities" | grep -oE '"Developer ID Application:[^"]*"' | head -n 1 | tr -d '"' || true)
fi

if [[ -n "$DMG_SIGN_ID" && "$DMG_SIGN_ID" != "-" ]]; then
  echo "==> Codesigning DMG container with: $DMG_SIGN_ID"
  codesign --force --timestamp --sign "$DMG_SIGN_ID" --identifier "app.lucent.macos.dmg" "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"
echo "Packaged $DMG_PATH ($(cat "${DMG_PATH}.sha256"))."
