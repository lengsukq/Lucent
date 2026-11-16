#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DEMO_ROOT/.." && pwd)"
DIST_DIR="$DEMO_ROOT/dist"
REGISTRY_FILE="$DEMO_ROOT/lumakey-registry.json"

chmod +x \
  "$DEMO_ROOT/browser-hub/run.sh" \
  "$DEMO_ROOT/lumalink-companion/run.sh" \
  "$DEMO_ROOT/notion-bookmarks/run.sh"

MCP_BIN="$REPO_ROOT/dist/Lumakey.app/Contents/MacOS/lumakey-mcp"
if [[ ! -x "$MCP_BIN" ]]; then
  swift build -c debug --arch arm64 --package-path "$REPO_ROOT" --product lumakey-mcp
  MCP_BIN="$(swift build -c debug --arch arm64 --package-path "$REPO_ROOT" --show-bin-path)/lumakey-mcp"
fi

mkdir -p "$DIST_DIR"
rm -f "$REGISTRY_FILE"

printf '%s\n' \
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"lumakey_package_plugin_for_store\",\"arguments\":{\"id\":\"browser-hub\",\"outputDir\":\"$DIST_DIR\",\"registryPath\":\"$REGISTRY_FILE\",\"storeId\":\"lumakey-demo-store\",\"storeName\":\"Lumakey 官方示例商店 (plugin-demo)\",\"maintainer\":\"Lumakey Official\",\"downloadURL\":\"./dist/browser-hub.zip\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"lumakey_package_plugin_for_store\",\"arguments\":{\"id\":\"lumalink-companion\",\"outputDir\":\"$DIST_DIR\",\"registryPath\":\"$REGISTRY_FILE\",\"storeId\":\"lumakey-demo-store\",\"storeName\":\"Lumakey 官方示例商店 (plugin-demo)\",\"maintainer\":\"Lumakey Official\",\"downloadURL\":\"./dist/lumalink-companion.zip\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"lumakey_package_plugin_for_store\",\"arguments\":{\"id\":\"notion-bookmarks\",\"outputDir\":\"$DIST_DIR\",\"registryPath\":\"$REGISTRY_FILE\",\"storeId\":\"lumakey-demo-store\",\"storeName\":\"Lumakey 官方示例商店 (plugin-demo)\",\"maintainer\":\"Lumakey Official\",\"downloadURL\":\"./dist/notion-bookmarks.zip\"}}}" \
  | "$MCP_BIN" --plugins-dir "$DEMO_ROOT" >/dev/null

echo "Updated $REGISTRY_FILE and $DIST_DIR/*.zip"
