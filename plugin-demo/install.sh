#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="${1:-all}"
DEST_ROOT="$HOME/Library/Application Support/Lucent/Plugins"
DATA_ROOT="$HOME/Library/Application Support/Lucent/PluginData"

ALL_PLUGINS=(
  "antigravity-pulse"
  "audio-presets"
  "file-shelf"
  "browser-hub"
  "gold-monitor"
  "local-send"
  "lumalink-companion"
  "notion-bookmarks"
  "translate-hub"
  "mac-pilot"
  "quick-remind"
  "screen-shield"
  "window-snap"
)

ensure_binary() {
  local id="$1"
  local bin_path="$DEMO_ROOT/$id/bin/$id"
  if [[ ! -x "$bin_path" ]]; then
    echo "==> Compiling native Swift binary for '$id'..."
    swift build -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --package-path "$DEMO_ROOT" --product "$id"
    local built_dir
    built_dir="$(swift build -c release --arch arm64 --package-path "$DEMO_ROOT" --show-bin-path)"
    mkdir -p "$DEMO_ROOT/$id/bin"
    cp "$built_dir/$id" "$bin_path"
    chmod 755 "$bin_path"
    /usr/bin/strip -x "$bin_path"
    codesign --force --sign "${LUCENT_SIGN_IDENTITY:--}" --identifier "app.lucent.plugin.$id" "$bin_path"
  fi
}

install_one() {
  local id="$1"
  local src_dir="$DEMO_ROOT/$id"
  local dest_dir="$DEST_ROOT/$id"
  if [[ ! -f "$src_dir/plugin.json" ]]; then
    echo "ERROR: 未找到插件示例：$src_dir/plugin.json" >&2
    exit 1
  fi
  ensure_binary "$id"
  mkdir -p "$DEST_ROOT"
  rm -rf "$dest_dir"
  cp -R "$src_dir" "$dest_dir"
  chmod 755 "$dest_dir/bin/$id"
  echo "已安装原生 Swift 插件 '$id' 到：$dest_dir"
}

if [[ "$PLUGIN_ID" == "all" ]]; then
  for pid in "${ALL_PLUGINS[@]}"; do
    install_one "$pid"
  done
else
  install_one "$PLUGIN_ID"
fi

echo "若 Lucent 正在运行，插件中心将在 350ms 内自动热重载。"
