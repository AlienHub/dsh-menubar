#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <Sparkle.framework> <codesign identity> [runtime: 0|1]" >&2
  exit 64
fi

FRAMEWORK="$1"
IDENTITY="$2"
RUNTIME="${3:-0}"
VERSION_ROOT="$FRAMEWORK/Versions/B"

if [ ! -d "$FRAMEWORK" ] || [ ! -x "$VERSION_ROOT/Sparkle" ]; then
  echo "Sparkle framework is missing or incomplete: $FRAMEWORK" >&2
  exit 1
fi

SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$RUNTIME" = "1" ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi

if [ -d "$VERSION_ROOT/XPCServices/Installer.xpc" ]; then
  codesign "${SIGN_ARGS[@]}" "$VERSION_ROOT/XPCServices/Installer.xpc"
fi

if [ -d "$VERSION_ROOT/XPCServices/Downloader.xpc" ]; then
  codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$VERSION_ROOT/XPCServices/Downloader.xpc"
fi

codesign "${SIGN_ARGS[@]}" "$VERSION_ROOT/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$VERSION_ROOT/Updater.app"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign --verify --deep --strict --verbose=2 "$FRAMEWORK"
