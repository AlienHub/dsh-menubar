#!/bin/bash
# DSH menu bar helper: extend the /api Host trust fence so *.localhost is trusted.
# RFC 6761 guarantees .localhost only ever resolves to loopback, so this is safe.
# Idempotent: repeated runs are no-ops.
set -euo pipefail

TARGET=$(find "$HOME/.npm/_npx" -path "*/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js" 2>/dev/null | head -1)
if [ -z "$TARGET" ]; then
  echo "patch: dsh-client-connection not found" >&2
  exit 0
fi

python3 - "$TARGET" <<'PY'
import sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
old = 'if (hostname === "localhost" || hostname === "[::1]") return true;'
new = 'if (hostname === "localhost" || hostname === "[::1]" || hostname.endsWith(".localhost")) return true;'
if new in src:
    print("patch: already applied")
elif old in src:
    open(path, "w", encoding="utf-8").write(src.replace(old, new))
    print("patch: applied ->", path)
else:
    print("patch: PATTERN NOT FOUND ->", path, file=sys.stderr)
PY
