#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:$HOME/.nvm/versions/node/v24.22.1/bin:/opt/homebrew/bin:$PATH"
CA_FILE="/etc/ssl/cert.pem"
[[ -f "/opt/homebrew/etc/ca-certificates/cert.pem" ]] && CA_FILE="/opt/homebrew/etc/ca-certificates/cert.pem"
export NODE_EXTRA_CA_CERTS="$CA_FILE"

BROWSER_BIN="$(find /Volumes/lightlsle/dependencies/remotion-browser -maxdepth 5 \( -name "chrome-headless-shell" -o -name "Google Chrome for Testing" \) -type f 2>/dev/null | head -n 1 || true)"
if [[ -z "$BROWSER_BIN" ]]; then
  echo "ERROR: No Remotion browser binary found in /Volumes/lightlsle/dependencies/remotion-browser" >&2
  exit 1
fi

OUT_DIR="$REPO_ROOT/dist/promo"
TMP_MP4="$PROJECT_DIR/out/lucent-promo-raw.mp4"
FINAL_MP4="$OUT_DIR/lucent-promo-1080p60.mp4"
mkdir -p "$OUT_DIR" "$PROJECT_DIR/out"

cd "$PROJECT_DIR"
echo "==> 1/4 TypeScript strict check"
npx tsc --noEmit

echo "==> 2/4 Synthesizing & mastering audio track (-14 LUFS)"
node scripts/generate-audio.mjs

echo "==> 3/4 Rendering 15,000 frames @ 1920x1080 60fps via Remotion"
npx remotion render src/index.ts LucentPromo "$TMP_MP4" \
  --browser-executable="$BROWSER_BIN" \
  --codec=h264 \
  --crf=17 \
  --pixel-format=yuv420p \
  --audio-codec=aac \
  --audio-bitrate=256k \
  --concurrency=6 \
  --jpeg-quality=94

echo "==> 4/4 Remuxing with +faststart for instant web/Bilibili/YouTube streaming"
ffmpeg -y -hide_banner -loglevel error \
  -i "$TMP_MP4" \
  -c copy -movflags +faststart \
  "$FINAL_MP4"
rm -f "$TMP_MP4"

echo "==> Render complete: $FINAL_MP4"
ffprobe -v error \
  -show_entries format=duration,size,bit_rate \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -of default=nw=1 "$FINAL_MP4"
