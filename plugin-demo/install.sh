#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="${1:-all}"
DEST_ROOT="$HOME/Library/Application Support/Lumakey/Plugins"

ALL_PLUGINS=(
  "browser-hub"
  "lumalink-companion"
  "notion-bookmarks"
  "translate-hub"
  "mac-pilot"
  "quick-remind"
  "screen-shield"
)

install_one() {
  local id="$1"
  local src_dir="$DEMO_ROOT/$id"
  local dest_dir="$DEST_ROOT/$id"
  if [[ ! -f "$src_dir/plugin.json" ]]; then
    echo "ERROR: 未找到插件示例：$src_dir/plugin.json" >&2
    exit 1
  fi
  mkdir -p "$DEST_ROOT"
  rm -rf "$dest_dir"
  cp -R "$src_dir" "$dest_dir"
  chmod +x "$dest_dir/run.sh"
  echo "已安装插件 '$id' 到：$dest_dir"
}

if [[ "$PLUGIN_ID" == "all" ]]; then
  for pid in "${ALL_PLUGINS[@]}"; do
    install_one "$pid"
  done
else
  install_one "$PLUGIN_ID"
fi

echo "若 Lumakey 正在运行，插件中心将在 350ms 内自动热重载。"
