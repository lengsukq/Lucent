#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/Lucent.app"
DMG_PATH="$ROOT_DIR/dist/Lucent.dmg"

echo "==> 1/3 Building redistributable Lucent.app (--distribution)"
LUCENT_DISTRIBUTION=1 bash "$ROOT_DIR/scripts/build-macos.sh" --distribution

SIGN_INFO="$(codesign -dvv "$APP_DIR" 2>&1 || true)"
IS_DEV_ID=0
if printf '%s\n' "$SIGN_INFO" | grep -Fq "Authority=Developer ID Application:"; then
  IS_DEV_ID=1
fi

echo "==> 2/3 Packaging redistributable DMG"
bash "$ROOT_DIR/scripts/package-dmg.sh" "$DMG_PATH"

if [[ "$IS_DEV_ID" == "1" ]]; then
  NOTARY_ARGS=()
  if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$APPLE_NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi

  if (( ${#NOTARY_ARGS[@]} > 0 )); then
    echo "==> 3/3 Submitting $DMG_PATH to Apple Notary Service (notarytool)..."
    xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait
    echo "==> Stapling notarization ticket onto $DMG_PATH..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -t open --context context:primary-signature -v "$DMG_PATH" || true
    shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"
    echo ""
    echo "✓ Official Notarized Release Ready: $DMG_PATH"
    echo "  SHA-256: $(cat "${DMG_PATH}.sha256")"
  else
    echo ""
    echo "⚠ Signed with Developer ID Application, but notarytool credentials were not set."
    echo "  Store credentials once in Keychain:"
    echo "    xcrun notarytool store-credentials \"lucent-notary\" --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>"
    echo "  Then re-run:"
    echo "    APPLE_NOTARY_PROFILE=\"lucent-notary\" bash scripts/release-macos.sh"
  fi
else
  echo ""
  echo "✓ Open-Source Community Release Ready (no Developer ID certificate in Keychain): $DMG_PATH"
  echo "  SHA-256: $(cat "${DMG_PATH}.sha256")"
  echo "  Note for recipients without Apple notarization:"
  echo "    Drag Lucent.app to /Applications, then right-click -> Open (or run: xattr -cr /Applications/Lucent.app)."
  echo "  To build a zero-prompt Gatekeeper notarized release later, install a 'Developer ID Application' certificate"
  echo "  in Keychain and run: APPLE_NOTARY_PROFILE=\"lucent-notary\" bash scripts/release-macos.sh"
fi
