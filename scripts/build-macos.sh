#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Lumakey only builds on Apple Silicon (arm64)." >&2
  exit 1
fi

DISTRIBUTION_MODE="${LUMAKEY_DISTRIBUTION:-1}"
if [[ "${1:-}" == "--distribution" ]]; then
  DISTRIBUTION_MODE="1"
elif [[ "${1:-}" == "--local-dev" ]]; then
  DISTRIBUTION_MODE="0"
fi

EXTRA_SPM_ARGS=()
if [[ -n "${LUMAKEY_SPM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_SPM_ARGS=(${LUMAKEY_SPM_EXTRA_ARGS})
fi

echo "==> Building release binaries (arm64, -O + dead_strip)"
swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --product Lumakey
swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --product lumakey-mcp

BIN_DIR="$(swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c release --arch arm64 --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/Lumakey.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
ENTITLEMENTS_PLIST="$ROOT_DIR/apps/macos/Lumakey.entitlements"
ICONSET_DIR="${TMPDIR:-/tmp}/lumakey-iconset-$$/Lumakey.iconset"

rm -rf "$APP_DIR" "$(dirname "$ICONSET_DIR")"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR" "$ICONSET_DIR"

echo "==> Generating Retina AppIcon.icns"
GEN_ICON_BIN="${TMPDIR:-/tmp}/lumakey-gen-icon-$$"
swiftc -module-cache-path "${TMPDIR:-/tmp}/lumakey-modcache" "$ROOT_DIR/scripts/generate-icon.swift" -o "$GEN_ICON_BIN"
"$GEN_ICON_BIN" "$ICONSET_DIR"
rm -f "$GEN_ICON_BIN"

if ! /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null; then
  PACK_ICNS_SRC="${TMPDIR:-/tmp}/lumakey-pack-icns-$$.swift"
  PACK_ICNS_BIN="${TMPDIR:-/tmp}/lumakey-pack-icns-$$"
  cat > "$PACK_ICNS_SRC" <<'SWIFT'
import AppKit
import Foundation
import ImageIO

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let slots: [(String, Double)] = [
    ("icon_16x16.png", 72.0), ("icon_16x16@2x.png", 144.0),
    ("icon_32x32.png", 72.0), ("icon_32x32@2x.png", 144.0),
    ("icon_128x128.png", 72.0), ("icon_128x128@2x.png", 144.0),
    ("icon_256x256.png", 72.0), ("icon_256x256@2x.png", 144.0),
    ("icon_512x512.png", 72.0), ("icon_512x512@2x.png", 144.0)
]
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "com.apple.icns" as CFString, slots.count, nil) else {
    exit(1)
}
for (name, dpi) in slots {
    let url = iconset.appendingPathComponent(name)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }
    CGImageDestinationAddImage(dest, cg, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { exit(1) }
SWIFT
  swiftc -module-cache-path "${TMPDIR:-/tmp}/lumakey-modcache" "$PACK_ICNS_SRC" -o "$PACK_ICNS_BIN"
  "$PACK_ICNS_BIN" "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"
  rm -f "$PACK_ICNS_SRC" "$PACK_ICNS_BIN"
fi
rm -rf "$(dirname "$ICONSET_DIR")"

cp "$ROOT_DIR/apps/macos/Info.plist" "$CONTENTS_DIR/Info.plist"
for lproj in zh-Hans.lproj en.lproj; do
  if [[ -d "$ROOT_DIR/apps/macos/$lproj" ]]; then
    rm -rf "$RESOURCES_DIR/$lproj"
    cp -R "$ROOT_DIR/apps/macos/$lproj" "$RESOURCES_DIR/$lproj"
  fi
done
if [[ -f "$ROOT_DIR/plugin-demo/lumakey-registry.json" && -d "$ROOT_DIR/plugin-demo/dist" ]]; then
  rm -rf "$RESOURCES_DIR/plugin-demo"
  mkdir -p "$RESOURCES_DIR/plugin-demo"
  cp "$ROOT_DIR/plugin-demo/lumakey-registry.json" "$RESOURCES_DIR/plugin-demo/lumakey-registry.json"
  cp -R "$ROOT_DIR/plugin-demo/dist" "$RESOURCES_DIR/plugin-demo/dist"
fi
if [[ -n "${LUMAKEY_BUNDLE_SHORT_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $LUMAKEY_BUNDLE_SHORT_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "${LUMAKEY_BUNDLE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $LUMAKEY_BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
fi
cp "$BIN_DIR/Lumakey" "$MACOS_DIR/Lumakey"
cp "$BIN_DIR/lumakey-mcp" "$MACOS_DIR/lumakey-mcp"
chmod +x "$MACOS_DIR/Lumakey" "$MACOS_DIR/lumakey-mcp"
/usr/bin/strip -x "$MACOS_DIR/Lumakey" "$MACOS_DIR/lumakey-mcp"

RDP_HELPER_SRC=""
for candidate in \
  "${LUMAKEY_RDP_HELPER_SRC:-}" \
  "$HOME/Library/Application Support/Lumakey/Remote/macos-rdp-daemon" \
  "$HOME/.local/share/lumakey/macos-rdp-daemon" \
  "/opt/homebrew/bin/macos-rdp-daemon" \
  "/opt/homebrew/sbin/macos-rdp-daemon" \
  "/usr/local/bin/macos-rdp-daemon" \
  "/usr/local/sbin/macos-rdp-daemon" \
  "/Volumes/lightlsle/dependencies/build/macos-rdp-server-macos14-final/macos-rdp-daemon"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    RDP_HELPER_SRC="$candidate"
    break
  fi
done
if [[ -n "$RDP_HELPER_SRC" ]]; then
  cp "$RDP_HELPER_SRC" "$HELPERS_DIR/macos-rdp-daemon"
  chmod +x "$HELPERS_DIR/macos-rdp-daemon"
  echo "==> Embedded RDP helper: $HELPERS_DIR/macos-rdp-daemon"
fi

for bin in Lumakey lumakey-mcp; do
  archs=$(lipo -archs "$MACOS_DIR/$bin")
  if [[ "$archs" != "arm64" ]]; then
    echo "ERROR: $bin architecture is '$archs', expected 'arm64'." >&2
    exit 1
  fi
done

select_signing_identity() {
  if [[ -n "${LUMAKEY_SIGN_IDENTITY:-}" ]]; then
    echo "$LUMAKEY_SIGN_IDENTITY"
    return
  fi
  local identities
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  local match
  if [[ "$DISTRIBUTION_MODE" == "1" ]]; then
    # For public distribution, ONLY use an official Apple Developer ID Application certificate (or clean '-' ad-hoc for open-source builds).
    # Never embed personal machine self-signed or Apple Development certificates into redistributable packages.
    match=$(printf '%s\n' "$identities" | grep -oE '"Developer ID Application:[^"]*"' | head -n 1 | tr -d '"' || true)
    if [[ -n "$match" ]]; then
      echo "$match"
    else
      echo "-"
    fi
    return
  fi

  for pattern in '"Developer ID Application:[^"]*"' '"Apple Development:[^"]*"' '"Mac Developer:[^"]*"' '"Lumakey Local Signer"'; do
    match=$(printf '%s\n' "$identities" | grep -oE "$pattern" | head -n 1 | tr -d '"' || true)
    if [[ -n "$match" ]]; then
      echo "$match"
      return
    fi
  done
  echo "-"
}

SIGN_ID="$(select_signing_identity)"
CODESIGN_RUNTIME_FLAGS=()
if [[ "$SIGN_ID" == "Developer ID Application:"* || "${LUMAKEY_HARDENED_RUNTIME:-0}" == "1" ]]; then
  CODESIGN_RUNTIME_FLAGS=(--options runtime --timestamp)
  echo "==> Codesigning for distribution with Hardened Runtime + Timestamp: $SIGN_ID"
elif [[ "$SIGN_ID" == "-" ]]; then
  if [[ "$DISTRIBUTION_MODE" == "1" ]]; then
    echo "==> Building clean Open-Source Community bundle (Ad-hoc '-', no Developer ID certificate detected in Keychain)"
  else
    echo "==> Ad-hoc codesigning local build ('-')"
  fi
else
  echo "==> Codesigning local build with Keychain identity: $SIGN_ID"
fi

if [[ -x "$HELPERS_DIR/macos-rdp-daemon" ]]; then
  codesign --force ${CODESIGN_RUNTIME_FLAGS[@]+"${CODESIGN_RUNTIME_FLAGS[@]}"} --sign "$SIGN_ID" --identifier "app.lumakey.macos.rdp" "$HELPERS_DIR/macos-rdp-daemon"
fi
codesign --force ${CODESIGN_RUNTIME_FLAGS[@]+"${CODESIGN_RUNTIME_FLAGS[@]}"} --sign "$SIGN_ID" --identifier "app.lumakey.macos.mcp" "$MACOS_DIR/lumakey-mcp"
codesign --force ${CODESIGN_RUNTIME_FLAGS[@]+"${CODESIGN_RUNTIME_FLAGS[@]}"} --entitlements "$ENTITLEMENTS_PLIST" --sign "$SIGN_ID" --identifier "app.lumakey.macos" "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"
codesign -d -r- "$APP_DIR" 2>&1 || true
plutil -lint "$CONTENTS_DIR/Info.plist"
plutil -lint "$ENTITLEMENTS_PLIST"
plutil -lint "$RESOURCES_DIR/zh-Hans.lproj/Localizable.strings"
plutil -lint "$RESOURCES_DIR/en.lproj/Localizable.strings"

echo "Built $APP_DIR successfully (mode=$( [[ "$DISTRIBUTION_MODE" == "1" ]] && echo "distribution" || echo "local" ), sign='$SIGN_ID')."
