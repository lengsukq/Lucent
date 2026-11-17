#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_BIN=""
for candidate in "${LUMAKEY_PYTHON3:-}" /Library/Developer/CommandLineTools/usr/bin/python3 /Applications/Xcode.app/Contents/Developer/usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /usr/bin/python3; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then PY_BIN="$candidate"; break; fi
done
exec "$PY_BIN" "$SCRIPT_DIR/quick_remind.py" "$@"
