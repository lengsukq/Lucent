#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS_ROOT="/Volumes/lightlsle/dependencies"
NPM_CACHE_DIR="$DEPS_ROOT/npm"
BROWSER_CACHE_DIR="$DEPS_ROOT/remotion-browser"

export PATH="/opt/homebrew/opt/node@24/bin:$HOME/.nvm/versions/node/v24.22.1/bin:/opt/homebrew/bin:$PATH"

if [[ ! -d "/Volumes/lightlsle" ]]; then
  echo "ERROR: External drive /Volumes/lightlsle is not mounted." >&2
  exit 1
fi

mkdir -p "$NPM_CACHE_DIR" "$BROWSER_CACHE_DIR/chrome-headless-shell"
export NPM_CONFIG_CACHE="$NPM_CACHE_DIR"
export npm_config_cache="$NPM_CACHE_DIR"

echo "==> Node: $(node -v) | npm: $(npm -v) | ffmpeg: $(ffmpeg -version | head -n 1)"
cd "$PROJECT_DIR"
npm install --no-audit --no-fund

rm -rf "$PROJECT_DIR/node_modules/.remotion"
ln -s "$BROWSER_CACHE_DIR" "$PROJECT_DIR/node_modules/.remotion"

EXISTING="$(find "$BROWSER_CACHE_DIR" -maxdepth 5 -name "chrome-headless-shell" -type f 2>/dev/null | head -n 1 || true)"
if [[ -z "$EXISTING" ]]; then
  ZIP="$BROWSER_CACHE_DIR/chrome-headless-shell-mac-arm64.zip"
  echo "==> Downloading Chrome Headless Shell (arm64) to $BROWSER_CACHE_DIR ..."
  curl -fSL "https://registry.npmmirror.com/-/binary/chrome-for-testing/158.0.8127.36/mac-arm64/chrome-headless-shell-mac-arm64.zip" -o "$ZIP"
  unzip -oq "$ZIP" -d "$BROWSER_CACHE_DIR/chrome-headless-shell/"
  rm -f "$ZIP"
  find "$BROWSER_CACHE_DIR" -maxdepth 5 -name "chrome-headless-shell" -type f -exec chmod +x {} \;
fi

echo "==> Browser ready:"
find "$BROWSER_CACHE_DIR" -maxdepth 5 -name "chrome-headless-shell" -type f
