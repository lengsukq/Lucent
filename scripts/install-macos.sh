#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/Lumakey.app"
DMG_PATH="$ROOT_DIR/dist/Lumakey.dmg"
DEST_APP="/Applications/Lumakey.app"

if [[ "${1:-}" != "--skip-build" || ! -d "$APP_DIR" ]]; then
  bash "$ROOT_DIR/scripts/build-macos.sh"
fi

bash "$ROOT_DIR/scripts/package-dmg.sh" "$DMG_PATH"

echo "==> Stopping any running Lumakey instances"
if pgrep -x Lumakey >/dev/null 2>&1; then
  pkill -TERM -x Lumakey || true
  for _ in $(seq 1 20); do
    if ! pgrep -x Lumakey >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  pkill -KILL -x Lumakey >/dev/null 2>&1 || true
fi

echo "==> Installing to $DEST_APP (in-place sync)"
mkdir -p "$DEST_APP"
rsync -a --delete "$APP_DIR/" "$DEST_APP/"

echo "==> Verifying installed bundle & signature"
codesign --verify --deep --strict "$DEST_APP"
archs=$(lipo -archs "$DEST_APP/Contents/MacOS/Lumakey")
if [[ "$archs" != "arm64" ]]; then
  echo "ERROR: Installed Lumakey architecture is '$archs', expected 'arm64'." >&2
  exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" || true
fi

echo "Installed $DEST_APP and packaged $DMG_PATH successfully."
