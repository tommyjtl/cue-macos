#!/usr/bin/env bash
set -euo pipefail

# Install the latest Debug build to a stable path so macOS TCC grants survive rebuilds.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$HOME/Applications/Cue Dev.app}"

DERIVED="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/Cue.app' -type d 2>/dev/null | head -1 || true)"
if [[ -z "$DERIVED" && -d "$ROOT/build" ]]; then
  DERIVED="$(find "$ROOT/build" -path '*/Build/Products/Debug/Cue.app' -type d 2>/dev/null | head -1 || true)"
fi

if [[ -z "$DERIVED" ]]; then
  echo "error: build Cue in Xcode first (Debug, ⌘B or ⌘R)" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
ditto "$DERIVED" "$DEST"

echo "Installed: $DEST"
echo "Open from Finder or run: open \"$DEST\""
echo "Grant permissions once for this copy — they should survive incremental Xcode builds."
