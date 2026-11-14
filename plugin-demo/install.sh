#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="${1:-notion-bookmarks}"
SRC_DIR="$DEMO_ROOT/$PLUGIN_ID"
DEST_ROOT="$HOME/Library/Application Support/Lumakey/Plugins"
DEST_DIR="$DEST_ROOT/$PLUGIN_ID"

if [[ ! -f "$SRC_DIR/plugin.json" ]]; then
  echo "ERROR: 未找到插件示例：$SRC_DIR/plugin.json" >&2
  exit 1
fi

mkdir -p "$DEST_ROOT"
rm -rf "$DEST_DIR"
cp -R "$SRC_DIR" "$DEST_DIR"
chmod +x "$DEST_DIR/run.sh"

echo "已安装插件 '$PLUGIN_ID' 到：$DEST_DIR"
echo "若 Lumakey 正在运行，插件中心将在 350ms 内自动热重载。"
