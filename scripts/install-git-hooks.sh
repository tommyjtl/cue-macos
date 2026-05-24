#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/scripts/hooks"

chmod +x "$HOOKS_DIR"/pre-push "$ROOT/scripts"/*.sh 2>/dev/null || true
git -C "$ROOT" config core.hooksPath scripts/hooks

echo "Installed git hooks from $HOOKS_DIR"
echo "  (Releases are manual via GitHub Actions — no pre-push version check)"
