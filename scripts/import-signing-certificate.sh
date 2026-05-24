#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_CERTIFICATE_BASE64:?APPLE_CERTIFICATE_BASE64 is required}"
: "${APPLE_CERTIFICATE_PASSWORD:?APPLE_CERTIFICATE_PASSWORD is required}"

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 32)}"
CERTIFICATE_PATH="${RUNNER_TEMP:-/tmp}/build_certificate.p12"
KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/app-signing.keychain-db"

echo -n "$APPLE_CERTIFICATE_BASE64" | base64 --decode -o "$CERTIFICATE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -P "$APPLE_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH" \
  >/dev/null 2>&1
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1
security list-keychain -d user -s "$KEYCHAIN_PATH"

security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" || {
  echo "error: Developer ID Application certificate not found in CI keychain" >&2
  exit 1
}

echo "Signing certificate imported into $KEYCHAIN_PATH"
