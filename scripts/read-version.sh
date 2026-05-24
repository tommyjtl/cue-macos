#!/usr/bin/env bash
# Reads MARKETING_VERSION from Config/Version.xcconfig.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/Config/Version.xcconfig"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: missing $VERSION_FILE" >&2
  exit 1
fi

MARKETING_VERSION="$(
  grep '^MARKETING_VERSION' "$VERSION_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]'
)"
BUILD_NUMBER="$(
  grep '^CURRENT_PROJECT_VERSION' "$VERSION_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]'
)"

if [[ -z "$MARKETING_VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "error: could not parse version from $VERSION_FILE" >&2
  exit 1
fi

RELEASE_TAG="v${MARKETING_VERSION}"
