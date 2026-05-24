#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/read-version.sh
source "$ROOT/scripts/read-version.sh"

OUTPUT="${1:-$ROOT/dist/release-notes.md}"
PREV_TAG="${2:-}"
BASIC=false

if [[ "${1:-}" == "--basic" ]]; then
  BASIC=true
  OUTPUT="${2:-$ROOT/dist/release-notes.md}"
  PREV_TAG="${3:-}"
fi

mkdir -p "$(dirname "$OUTPUT")"

if [[ -z "$PREV_TAG" ]]; then
  PREV_TAG="$(git tag --list 'v*' --sort=-version:refname | head -1 || true)"
fi

if [[ -n "$PREV_TAG" ]]; then
  COMMIT_LOG="$(git log "${PREV_TAG}..HEAD" --pretty=format:'- %s (%an, %h)' --no-merges)"
  RANGE="$PREV_TAG..HEAD"
else
  COMMIT_LOG="$(git log --pretty=format:'- %s (%an, %h)' --no-merges)"
  RANGE="initial history"
fi

if [[ -z "$COMMIT_LOG" ]]; then
  COMMIT_LOG="- No commits found in range"
fi

if [[ "$BASIC" == true ]]; then
  {
    printf '# Cue %s (build %s)\n\n## Changes\n\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
    printf '%s\n' "$COMMIT_LOG"
    cat <<'EOF'

---

This build is **unsigned**. After installing, you may need to right-click the app and choose **Open**, or allow it in **System Settings → Privacy & Security**.
EOF
  } >"$OUTPUT"
  echo "Wrote basic release notes to $OUTPUT"
  exit 0
fi

if [[ -z "${RELEASE_NOTES_API_KEY:-}" ]]; then
  echo "error: RELEASE_NOTES_API_KEY is not set" >&2
  exit 1
fi

PR_CONTEXT=""
if command -v gh >/dev/null 2>&1; then
  PR_CONTEXT="$(python3 "$ROOT/scripts/collect-release-pr-context.py" "${PREV_TAG:-}" 2>/dev/null || true)"
fi
if [[ -z "$PR_CONTEXT" ]]; then
  PR_CONTEXT="No merged pull request descriptions were collected (gh unavailable or no PRs in range)."
fi

PROMPT="$(cat <<EOF
You write GitHub release notes for Cue, a macOS menu-bar utility for capturing screen context and chatting with AI.

Version: ${MARKETING_VERSION} (build ${BUILD_NUMBER})
Commit range: ${RANGE}

Commits:
EOF
)"
PROMPT+=$(printf '%s\n' "$COMMIT_LOG")
PROMPT+=$(printf '\n\nMerged pull requests:\n%s\n' "$PR_CONTEXT")
PROMPT+=$(cat <<'EOF'

Write release notes in Markdown with exactly these two sections:

## What's new
Audience: non-developer macOS users. Plain language, 3-6 bullet points max. Focus on user-visible changes. No jargon.

## For developers
Audience: contributors and developers. Technical bullets covering architecture, dependencies, build/signing, API changes, and migration notes if any.

Rules:
- Use only facts supported by the commit list and merged pull request descriptions; do not invent features.
- Prefer PR descriptions for user-facing detail when they add context beyond commit subjects.
- If the source material is sparse, say so briefly and keep bullets minimal.
- Do not wrap the whole response in a code fence.
EOF
)

REQUEST="$(python3 -c '
import json, sys
prompt = sys.argv[1]
print(json.dumps({
    "model": "gpt-4o-mini",
    "temperature": 0.2,
    "messages": [
        {"role": "system", "content": "You produce accurate, concise GitHub release notes."},
        {"role": "user", "content": prompt},
    ],
}))
' "$PROMPT")"

RESPONSE="$(curl -fsS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer ${RELEASE_NOTES_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$REQUEST")"

python3 -c '
import json, sys, pathlib
data = json.loads(sys.argv[1])
out = pathlib.Path(sys.argv[2])
version, build = sys.argv[3], sys.argv[4]
content = data["choices"][0]["message"]["content"].strip()
header = f"# Cue {version} (build {build})\n\n"
out.write_text(header + content + "\n", encoding="utf-8")
print(out)
' "$RESPONSE" "$OUTPUT" "$MARKETING_VERSION" "$BUILD_NUMBER"

echo "Wrote release notes to $OUTPUT"
