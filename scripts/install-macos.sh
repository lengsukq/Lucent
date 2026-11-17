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

# Detect whether the currently installed /Applications/Lumakey.app already uses a stable local signature
# BEFORE overwriting it, so local rebuilds preserve the user's own authorized certificate.
EXISTING_AUTH=""
if [[ -d "$DEST_APP" ]]; then
  CURRENT_INFO="$(codesign -dvv "$DEST_APP" 2>&1 || true)"
  if ! printf '%s\n' "$CURRENT_INFO" | grep -q 'Signature=adhoc'; then
    EXISTING_AUTH="$(printf '%s\n' "$CURRENT_INFO" | sed -n 's/^Authority=//p' | head -n 1 || true)"
  fi
fi

echo "==> Installing to $DEST_APP (in-place sync)"
mkdir -p "$DEST_APP"
rsync -a --delete "$APP_DIR/" "$DEST_APP/"

# Keep dist/Lumakey.dmg clean for public distribution (Plan 2), while preserving any existing
# authorized personal/local certificate on /Applications/Lumakey.app (never grabbing an ambiguous
# third-party certificate when multiple Apple Development identities exist in Keychain).
pick_local_install_identity() {
  local identities match count
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)

  if [[ -n "${LUMAKEY_SIGN_IDENTITY:-}" ]]; then
    echo "$LUMAKEY_SIGN_IDENTITY"
    return 0
  fi

  if [[ -n "$EXISTING_AUTH" ]] && printf '%s\n' "$identities" | grep -F "\"$EXISTING_AUTH\"" >/dev/null 2>&1; then
    echo "$EXISTING_AUTH"
    return 0
  fi

  if printf '%s\n' "$identities" | grep -F '"Lumakey Local Signer"' >/dev/null 2>&1; then
    echo "Lumakey Local Signer"
    return 0
  fi

  for pattern in '"Developer ID Application:[^"]*"' '"Apple Development:[^"]*"' '"Mac Developer:[^"]*"'; do
    match=$(printf '%s\n' "$identities" | grep -oE "$pattern" | tr -d '"' || true)
    count=$(printf '%s\n' "$match" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$count" == "1" ]]; then
      printf '%s\n' "$match" | head -n 1
      return 0
    fi
  done
  return 1
}

LOCAL_SIGN_ID="$(pick_local_install_identity || true)"
if [[ -n "$LOCAL_SIGN_ID" && "$LOCAL_SIGN_ID" != "-" ]]; then
  CURRENT_AUTH="$(codesign -dv --verbose=2 "$DEST_APP" 2>&1 || true)"
  if printf '%s\n' "$CURRENT_AUTH" | grep -q 'Signature=adhoc'; then
    echo "==> Re-signing local $DEST_APP with authorized Keychain identity '$LOCAL_SIGN_ID' to preserve TCC permissions"
    if [[ -x "$DEST_APP/Contents/Helpers/macos-rdp-daemon" ]]; then
      codesign --force --sign "$LOCAL_SIGN_ID" --identifier "app.lumakey.macos.rdp" "$DEST_APP/Contents/Helpers/macos-rdp-daemon"
    fi
    if [[ -x "$DEST_APP/Contents/MacOS/lumakey-mcp" ]]; then
      codesign --force --sign "$LOCAL_SIGN_ID" --identifier "app.lumakey.macos.mcp" "$DEST_APP/Contents/MacOS/lumakey-mcp"
    fi
    codesign --force --entitlements "$ROOT_DIR/apps/macos/Lumakey.entitlements" --sign "$LOCAL_SIGN_ID" --identifier "app.lumakey.macos" "$DEST_APP"
  fi
fi

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
