#!/usr/bin/env bash
# Fail when the current branch MARKETING_VERSION is not higher than the base branch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${1:-origin/main}"

read_marketing_version() {
  local file="$1"
  grep '^MARKETING_VERSION' "$file" | head -1 | cut -d= -f2 | tr -d '[:space:]'
}

if [[ ! -f "$ROOT/Config/Version.xcconfig" ]]; then
  echo "error: missing Config/Version.xcconfig" >&2
  exit 1
fi

CURRENT_VERSION="$(read_marketing_version "$ROOT/Config/Version.xcconfig")"
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "error: could not parse MARKETING_VERSION from current branch" >&2
  exit 1
fi

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "error: base ref not found: $BASE_REF" >&2
  exit 1
fi

BASE_VERSION="$(git show "${BASE_REF}:Config/Version.xcconfig" | read_marketing_version /dev/stdin)"
if [[ -z "$BASE_VERSION" ]]; then
  echo "error: could not parse MARKETING_VERSION from $BASE_REF" >&2
  exit 1
fi

echo "Current branch MARKETING_VERSION: $CURRENT_VERSION"
echo "Base branch MARKETING_VERSION:    $BASE_VERSION"

if [[ "$CURRENT_VERSION" == "$BASE_VERSION" ]]; then
  echo "error: MARKETING_VERSION ($CURRENT_VERSION) must be higher than $BASE_REF ($BASE_VERSION)." >&2
  echo "Bump Config/Version.xcconfig on this branch before merging to main." >&2
  exit 1
fi

HIGHER="$(printf '%s\n%s\n' "$CURRENT_VERSION" "$BASE_VERSION" | sort -V | tail -1)"
if [[ "$HIGHER" != "$CURRENT_VERSION" ]]; then
  echo "error: MARKETING_VERSION ($CURRENT_VERSION) must be higher than $BASE_REF ($BASE_VERSION)." >&2
  echo "Bump Config/Version.xcconfig on this branch before merging to main." >&2
  exit 1
fi

echo "Version check passed."
