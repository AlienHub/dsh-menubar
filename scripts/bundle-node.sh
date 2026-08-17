#!/bin/bash
# Bundle the official Node.js runtime into Resources so users don't need Node installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/node-runtime"
VER="22.21.1"
TARBALL="/tmp/node-v$VER-darwin-arm64.tar.gz"
URL="https://nodejs.org/dist/v$VER/node-v$VER-darwin-arm64.tar.gz"

if [ -f "$DEST/bin/node" ]; then
  echo "node runtime already bundled at $DEST"
  exit 0
fi

echo "downloading node v$VER (arm64) ..."
curl -L --fail -o "$TARBALL" "$URL"

echo "extracting ..."
rm -rf "$DEST" /tmp/node-extract
mkdir -p /tmp/node-extract
tar -xzf "$TARBALL" -C /tmp/node-extract
SRC="/tmp/node-extract/node-v$VER-darwin-arm64"

# Slim down: strip debug symbols, drop headers/docs/aux binaries.
strip "$SRC/bin/node" 2>/dev/null || true
rm -rf "$SRC/include" "$SRC/share" "$SRC/CHANGELOG.md" "$SRC/LICENSE" "$SRC/README.md" "$SRC/corepack" 2>/dev/null || true
# Apple Silicon requires an (ad-hoc) signature to execute arm64 binaries.
codesign --force --sign - "$SRC/bin/node"

mkdir -p "$(dirname "$DEST")"
mv "$SRC" "$DEST"
rm -f "$TARBALL"
echo "bundled node runtime at $DEST"
du -sh "$DEST"
