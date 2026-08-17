#!/bin/bash
# One-time setup: export the Developer ID signing identity and notarization key
# from your local keychain and upload them as GitHub secrets for dsh-menubar.
#
# Run this in your own Terminal (NOT headless): exporting the private key
# triggers a Keychain authorization prompt you must approve.
set -euo pipefail

REPO="${DSH_REPO:-AlienHub/dsh-menubar}"
IDENTITY="${DSH_SIGNING_IDENTITY:-Developer ID Application: Li Cao (Q5DR6Q529D)}"
P8_KEY="${DSH_NOTARY_P8:-$HOME/Apple-Dev/AuthKey_3S788PUHNT.p8}"
KEY_ID="${DSH_NOTARY_KEY_ID:-3S788PUHNT}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required: https://cli.github.com" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "Run 'gh auth login' first." >&2
  exit 1
fi
if [ ! -f "$P8_KEY" ]; then
  echo "Notary key not found: $P8_KEY" >&2
  exit 1
fi

echo "== 1/4 Exporting signing identity (approve the Keychain prompt) =="
P12_PATH="${TMPDIR:-/tmp}/dsh-signing.p12"
P12_PASSWORD="$(openssl rand -base64 24)"
security export   -k "$HOME/Library/Keychains/login.keychain-db"   -t identities -f pkcs12   -P "$P12_PASSWORD"   -o "$P12_PATH"   "$IDENTITY"

echo "== 2/4 Uploading signing secrets =="
base64 < "$P12_PATH" | gh secret set APPLE_SIGNING_P12_BASE64 -R "$REPO"
gh secret set APPLE_SIGNING_P12_PASSWORD -b "$P12_PASSWORD" -R "$REPO"

echo "== 3/4 Uploading notarization key =="
base64 < "$P8_KEY" | gh secret set APPLE_NOTARY_KEY_BASE64 -R "$REPO"
gh secret set APPLE_NOTARY_KEY_ID -b "$KEY_ID" -R "$REPO"

echo "== 4/4 Issuer ID =="
if [ -n "${DSH_NOTARY_ISSUER_ID:-}" ]; then
  gh secret set APPLE_NOTARY_ISSUER_ID -b "$DSH_NOTARY_ISSUER_ID" -R "$REPO"
else
  printf 'App Store Connect Issuer ID: '
  read -r ISSUER_ID
  gh secret set APPLE_NOTARY_ISSUER_ID -b "$ISSUER_ID" -R "$REPO"
fi

rm -f "$P12_PATH"
echo "Done. Secrets configured for $REPO."
