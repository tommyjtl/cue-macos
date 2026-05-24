#!/usr/bin/env bash
# Ensures MARKETING_VERSION is ahead of the latest release tag on the remote main branch
# when pushing new commits to main.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/read-version.sh
source "$ROOT/scripts/read-version.sh"

REMOTE="${1:-origin}"
MAIN_REF="$REMOTE/main"

git fetch "$REMOTE" main --tags --quiet 2>/dev/null || {
  echo "version-check: could not fetch $MAIN_REF; skipping remote comparison"
  exit 0
}

if ! git rev-parse --verify "$MAIN_REF" >/dev/null 2>&1; then
  echo "version-check: no $MAIN_REF yet; skipping"
  exit 0
fi

LATEST_TAG="$(
  git tag --list 'v*' --merged "$MAIN_REF" --sort=-version:refname | head -1 || true
)"

if [[ -z "$LATEST_TAG" ]]; then
  echo "version-check: no release tags on $MAIN_REF yet"
  exit 0
fi

LATEST_VERSION="${LATEST_TAG#v}"
LOCAL="$MARKETING_VERSION"

# Commits on this push not reachable from remote main (excluding the push itself).
mapfile -t PUSH_SHAS < <(git rev-list "$MAIN_REF..HEAD" 2>/dev/null || true)
if [[ ${#PUSH_SHAS[@]} -eq 0 ]]; then
  echo "version-check: no commits ahead of $MAIN_REF"
  exit 0
fi

if [[ "$(printf '%s\n' "$LOCAL" "$LATEST_VERSION" | sort -V | head -1)" == "$LOCAL" && "$LOCAL" != "$LATEST_VERSION" ]]; then
  cat >&2 <<EOF
error: pushing ${#PUSH_SHAS[@]} commit(s) to main but MARKETING_VERSION ($LOCAL) is not ahead of latest release ($LATEST_TAG).

Bump Config/Version.xcconfig before releasing to main:
  MARKETING_VERSION = <new version>
  CURRENT_PROJECT_VERSION = <increment build number>
EOF
  exit 1
fi

if [[ "$LOCAL" == "$LATEST_VERSION" ]]; then
  cat >&2 <<EOF
error: pushing new commits to main but MARKETING_VERSION ($LOCAL) matches latest release ($LATEST_TAG).

Bump Config/Version.xcconfig before releasing to main.
EOF
  exit 1
fi

echo "version-check: ok — releasing v$LOCAL (latest on $MAIN_REF is $LATEST_TAG)"
