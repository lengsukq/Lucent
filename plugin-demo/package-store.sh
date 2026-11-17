#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DEMO_ROOT/.." && pwd)"
DIST_DIR="$DEMO_ROOT/dist"
REGISTRY_FILE="$DEMO_ROOT/lumakey-registry.json"

PLUGINS=(
  "browser-hub"
  "lumalink-companion"
  "notion-bookmarks"
  "translate-hub"
  "mac-pilot"
  "quick-remind"
  "screen-shield"
)

for pid in "${PLUGINS[@]}"; do
  chmod +x "$DEMO_ROOT/$pid/run.sh"
done

MCP_BIN="$REPO_ROOT/dist/Lumakey.app/Contents/MacOS/lumakey-mcp"
if [[ ! -x "$MCP_BIN" ]]; then
  swift build ${LUMAKEY_SPM_EXTRA_ARGS:-} -c debug --arch arm64 --package-path "$REPO_ROOT" --product lumakey-mcp
  MCP_BIN="$(swift build ${LUMAKEY_SPM_EXTRA_ARGS:-} -c debug --arch arm64 --package-path "$REPO_ROOT" --show-bin-path)/lumakey-mcp"
fi

mkdir -p "$DIST_DIR"
rm -f "$REGISTRY_FILE" "$DIST_DIR"/*.zip

{
  req_id=1
  for pid in "${PLUGINS[@]}"; do
    printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"lumakey_package_plugin_for_store","arguments":{"id":"%s","outputDir":"%s","registryPath":"%s","storeId":"lumakey-demo-store","storeName":"Lumakey 官方示例商店 (plugin-demo)","maintainer":"Lumakey Official","downloadURL":"./dist/%s.zip"}}}\n' \
      "$req_id" "$pid" "$DIST_DIR" "$REGISTRY_FILE" "$pid"
    req_id=$((req_id + 1))
  done
} | "$MCP_BIN" --plugins-dir "$DEMO_ROOT" >/dev/null

echo "Updated $REGISTRY_FILE and $DIST_DIR/*.zip (${#PLUGINS[@]} plugins)"
