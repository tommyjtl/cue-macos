#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/scripts/hooks"

chmod +x "$HOOKS_DIR"/pre-push "$ROOT/scripts"/*.sh
git -C "$ROOT" config core.hooksPath scripts/hooks

echo "Installed git hooks from $HOOKS_DIR"
echo "  pre-push → scripts/check-version-ahead.sh (main only)"
