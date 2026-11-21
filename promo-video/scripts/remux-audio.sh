#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
export PATH="/opt/homebrew/opt/node@24/bin:$HOME/.nvm/versions/node/v24.22.1/bin:/opt/homebrew/bin:$PATH"

CA_FILE="/etc/ssl/cert.pem"
[[ -f "/opt/homebrew/etc/ca-certificates/cert.pem" ]] && CA_FILE="/opt/homebrew/etc/ca-certificates/cert.pem"
export NODE_EXTRA_CA_CERTS="$CA_FILE"

FINAL_MP4="$REPO_ROOT/dist/promo/lucent-promo-1080p60.mp4"
TMP_MP4="$PROJECT_DIR/out/lucent-promo-remux.mp4"
MASTER_WAV="$PROJECT_DIR/public/audio/generated/soundtrack-master.wav"

if [[ ! -f "$FINAL_MP4" ]]; then
  echo "ERROR: $FINAL_MP4 does not exist yet. Run scripts/render.sh first." >&2
  exit 1
fi

cd "$PROJECT_DIR"
echo "==> 1/2 Regenerating gentle female VO + serene ambient master..."
node scripts/generate-audio.mjs

echo "==> 2/2 Losslessly remuxing new audio onto existing 1080p60 H.264 video stream..."
mkdir -p "$PROJECT_DIR/out"
ffmpeg -y -hide_banner -loglevel error \
  -i "$FINAL_MP4" \
  -i "$MASTER_WAV" \
  -map 0:v:0 -map 1:a:0 \
  -c:v copy \
  -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -movflags +faststart \
  -shortest \
  "$TMP_MP4"

mv "$TMP_MP4" "$FINAL_MP4"

echo "==> Updated final video: $FINAL_MP4"
ffprobe -v error \
  -show_entries format=duration,size,bit_rate \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -of default=nw=1 "$FINAL_MP4"
ffmpeg -hide_banner -i "$FINAL_MP4" -af volumedetect -f null - 2>&1 | grep -E 'mean_volume|max_volume'
