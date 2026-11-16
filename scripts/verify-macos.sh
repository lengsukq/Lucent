#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Lumakey only supports Apple Silicon (arm64)." >&2
  exit 1
fi

if [[ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" == "1" ]]; then
  echo "ERROR: Rosetta translated shell is not allowed." >&2
  exit 1
fi

echo "==> Clean Code line limit check (Sources/**/*.swift <= 300 lines)"
while IFS= read -r -d '' file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  if (( lines > 300 )); then
    echo "ERROR: $file has $lines lines (exceeds Clean Code limit of 300)." >&2
    exit 1
  fi
done < <(find "$ROOT_DIR/Sources" -type f -name "*.swift" -print0)

echo "==> Checking acyclic module dependency boundaries"
python3 -B - <<'PY'
import pathlib, re, sys

allowed = {
    "LumakeyFoundation": set(),
    "LumakeySearch": {"LumakeyFoundation"},
    "LumakeySystem": {"LumakeyFoundation"},
    "LumakeyMedia": {"LumakeyFoundation", "LumakeySearch"},
    "LumakeyCore": {"LumakeyFoundation", "LumakeySearch", "LumakeyMedia", "LumakeySystem"},
    "Lumakey": {"LumakeyFoundation", "LumakeySearch", "LumakeyMedia", "LumakeySystem", "LumakeyCore"},
    "LumakeyMCP": {"LumakeyFoundation", "LumakeySearch", "LumakeyMedia", "LumakeySystem", "LumakeyCore"},
}
internal_modules = set(allowed.keys())
imp_re = re.compile(r"^\s*(?:@_exported\s+)?import\s+([A-Za-z0-9_]+)", re.MULTILINE)
errors = []

for mod, permitted in allowed.items():
    mod_dir = pathlib.Path("Sources") / mod
    if not mod_dir.exists():
        errors.append(f"Missing module directory: {mod_dir}")
        continue
    for sf in sorted(mod_dir.glob("*.swift")):
        text = sf.read_text(encoding="utf-8")
        for line in text.splitlines():
            for chunk in line.split(";"):
                m = imp_re.match(chunk)
                if m:
                    target = m.group(1)
                    if target in internal_modules and target != mod and target not in permitted:
                        errors.append(f"{sf}: forbidden upward/cross import '{target}' in module '{mod}'")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
print("Module DAG verified (LumakeyFoundation -> Search/System/Media -> Core -> App/MCP).")
PY

echo "==> Checking Info.plist, Entitlements & LICENSE"
plutil -lint "$ROOT_DIR/apps/macos/Info.plist"
plutil -lint "$ROOT_DIR/apps/macos/Lumakey.entitlements"
if [[ ! -f "$ROOT_DIR/LICENSE" || ! -f "$ROOT_DIR/CONTRIBUTING.md" ]]; then
  echo "ERROR: Missing root LICENSE or CONTRIBUTING.md." >&2
  exit 1
fi

echo "==> Checking documentation links and index coverage"
python3 -B "$ROOT_DIR/scripts/check-docs.py"

EXTRA_SPM_ARGS=()
if [[ -n "${LUMAKEY_SPM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_SPM_ARGS=(${LUMAKEY_SPM_EXTRA_ARGS})
fi

CHECK_ARGS=()
if [[ -n "${LUMAKEY_CHECK_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  CHECK_ARGS=(${LUMAKEY_CHECK_ARGS})
fi

echo "==> Running Swift Testing unit & performance baseline suite (LumakeyTests)"
swift test ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} --arch arm64

echo "==> Building Swift 6 executable targets (arm64 debug)"
swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c debug --arch arm64

BIN_DIR="$(swift build ${EXTRA_SPM_ARGS[@]+"${EXTRA_SPM_ARGS[@]}"} -c debug --arch arm64 --show-bin-path)"
for bin in Lumakey lumakey-mcp lumakey-check; do
  archs=$(lipo -archs "$BIN_DIR/$bin")
  if [[ "$archs" != "arm64" ]]; then
    echo "ERROR: $bin architecture is '$archs', expected 'arm64'." >&2
    exit 1
  fi
done

echo "==> Running LumakeyCheck + real lumakey-mcp subprocess verification"
"$BIN_DIR/lumakey-check" ${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"}
