#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DSHMenuBar.app"
BIN="$ROOT/.build/release/DSHMenuBar"

swift build -c release --package-path "$ROOT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DSHMenuBar"
cp "$ROOT/Resources/deepseek-whale.png" "$APP/Contents/Resources/deepseek-whale.png"
cp "$ROOT/scripts/patch-trust.sh" "$APP/Contents/Resources/patch-trust.sh"
if [ -d "$ROOT/Resources/node-runtime" ]; then
  echo "bundling node runtime ..."
  cp -R "$ROOT/Resources/node-runtime" "$APP/Contents/Resources/node-runtime"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>DSH Menu Bar</string>
<key>CFBundleExecutable</key><string>DSHMenuBar</string>
<key>CFBundleIdentifier</key><string>ai.deepseek.harness.menubar</string>
<key>CFBundleName</key><string>DSH Menu Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
printf 'Built %s\n' "$APP"
