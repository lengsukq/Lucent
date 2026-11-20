#!/usr/bin/env bash
set -euo pipefail

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DEMO_ROOT/.." && pwd)"
DIST_DIR="$DEMO_ROOT/dist"
STARTERS_DIST_DIR="$DEMO_ROOT/Starters"
REGISTRY_FILE="$DEMO_ROOT/lucent-registry.json"
SIGN_ID="${LUCENT_SIGN_IDENTITY:--}"

PLUGINS=(
  "antigravity-pulse"
  "audio-presets"
  "file-shelf"
  "browser-hub"
  "gold-monitor"
  "lumalink-companion"
  "notion-bookmarks"
  "translate-hub"
  "mac-pilot"
  "quick-remind"
  "screen-shield"
)

STARTERS=(
  "sys-ip-dns"
  "port-killer"
  "shell-note"
)

EXTRA_SPM_ARGS=()
if [[ -n "${LUCENT_SPM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_SPM_ARGS=(${LUCENT_SPM_EXTRA_ARGS})
fi

DEMO_SPM_ARGS=()
if [[ -n "${LUCENT_DEMO_SPM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  DEMO_SPM_ARGS=(${LUCENT_DEMO_SPM_EXTRA_ARGS})
elif [[ -n "${LUCENT_SPM_EXTRA_ARGS:-}" ]]; then
  DEMO_SPM_ARGS=("${EXTRA_SPM_ARGS[@]}")
fi

echo "==> Building native arm64 Swift demo & starter plugins (-O + dead_strip)"
swift build ${DEMO_SPM_ARGS[@]+"${DEMO_SPM_ARGS[@]}"} -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --package-path "$DEMO_ROOT"
DEMO_BIN_DIR="$(swift build ${DEMO_SPM_ARGS[@]+"${DEMO_SPM_ARGS[@]}"} -c release --arch arm64 --package-path "$DEMO_ROOT" --show-bin-path)"

for pid in "${PLUGINS[@]}"; do
  mkdir -p "$DEMO_ROOT/$pid/bin"
  cp "$DEMO_BIN_DIR/$pid" "$DEMO_ROOT/$pid/bin/$pid"
  chmod 755 "$DEMO_ROOT/$pid/bin/$pid"
  /usr/bin/strip -x "$DEMO_ROOT/$pid/bin/$pid"
  codesign --force --sign "$SIGN_ID" --identifier "app.lucent.plugin.$pid" "$DEMO_ROOT/$pid/bin/$pid"
done

mkdir -p "$STARTERS_DIST_DIR"
rm -f "$STARTERS_DIST_DIR"/*.zip
for sid in "${STARTERS[@]}"; do
  STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lc-starter-stage.XXXXXX")"
  mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/Sources"
  cp "$DEMO_BIN_DIR/$sid" "$STAGE_DIR/bin/$sid"
  chmod 755 "$STAGE_DIR/bin/$sid"
  /usr/bin/strip -x "$STAGE_DIR/bin/$sid"
  codesign --force --sign "$SIGN_ID" --identifier "app.lucent.starter.$sid" "$STAGE_DIR/bin/$sid"
  cp "$DEMO_ROOT/Starters/$sid/Sources/main.swift" "$STAGE_DIR/Sources/main.swift"
  /usr/bin/ditto -c -k --sequesterRsrc "$STAGE_DIR" "$STARTERS_DIST_DIR/$sid.zip"
  rm -rf "$STAGE_DIR"
done

MCP_BIN="${LUCENT_MCP_BIN:-}"
if [[ -z "$MCP_BIN" || ! -x "$MCP_BIN" ]]; then
  swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c debug --arch arm64 --package-path "$REPO_ROOT" --product lucent-mcp
  MCP_BIN="$(swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c debug --arch arm64 --package-path "$REPO_ROOT" --show-bin-path)/lucent-mcp"
fi

mkdir -p "$DIST_DIR"
rm -f "$REGISTRY_FILE" "$DIST_DIR"/*.zip

{
  req_id=1
  for pid in "${PLUGINS[@]}"; do
    printf '{"jsonrpc":"2.0","id":%d,"method":"tools/call","params":{"name":"lucent_package_plugin_for_store","arguments":{"id":"%s","outputDir":"%s","registryPath":"%s","storeId":"lucent-demo-store","storeName":"Lucent 官方示例商店 (plugin-demo)","maintainer":"Lucent Official","downloadURL":"./dist/%s.zip"}}}\n' \
      "$req_id" "$pid" "$DIST_DIR" "$REGISTRY_FILE" "$pid"
    req_id=$((req_id + 1))
  done
} | "$MCP_BIN" --plugins-dir "$DEMO_ROOT" >/dev/null

echo "Updated $REGISTRY_FILE, $DIST_DIR/*.zip (${#PLUGINS[@]} plugins), and $STARTERS_DIST_DIR/*.zip (${#STARTERS[@]} starters)"
