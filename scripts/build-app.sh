#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DSHMenuBar.app"
BIN="$ROOT/.build/release/DSHMenuBar"
VERSION="${DSH_APP_VERSION:-0.2.4}"

swift build -c release --package-path "$ROOT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/DSHMenuBar"
ditto "$ROOT/.build/release/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
<key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
<key>CFBundleVersion</key><string>VERSION_PLACEHOLDER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAllowsAutomaticUpdates</key><true/>
<key>SUAutomaticallyUpdate</key><true/>
<key>SUFeedURL</key><string>https://github.com/AlienHub/dsh-menubar/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>S0QWeuDtE18utTUucIg9aR4PvpFFQRsa0HXeav7IInc=</string>
<key>SURequireSignedFeed</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
</dict></plist>
PLIST
/usr/bin/sed -i '' "s/VERSION_PLACEHOLDER/$VERSION/g" "$APP/Contents/Info.plist"
IDENTITY="${DSH_CODESIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
  echo "Signing with identity: $IDENTITY"
  NODE_ENTITLEMENTS="$ROOT/Resources/node-runtime.entitlements.plist"
  "$ROOT/scripts/sign-sparkle-framework.sh" "$APP/Contents/Frameworks/Sparkle.framework" "$IDENTITY" 1
  # Node's V8 engine needs the JIT entitlement under the hardened runtime.
  while IFS= read -r macho; do
    case "$macho" in
      "$APP/Contents/Frameworks/Sparkle.framework"/*) continue ;;
    esac
    if [ "$macho" = "$APP/Contents/Resources/node-runtime/bin/node" ]; then
      codesign --force --sign "$IDENTITY" --options runtime --entitlements "$NODE_ENTITLEMENTS" --timestamp "$macho"
    else
      codesign --force --sign "$IDENTITY" --options runtime --timestamp "$macho"
    fi
  done < <(find "$APP" -type f -perm +111 2>/dev/null | while IFS= read -r f; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" && echo "$f"
  done)
  # Do not use --deep here: it would re-sign Node and discard its JIT entitlement.
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
else
  echo "No identity; signing ad hoc."
  codesign --force --deep --sign - "$APP" >/dev/null
fi
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
