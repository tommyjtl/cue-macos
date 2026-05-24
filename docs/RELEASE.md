# Releasing Cue

## Version source of truth

Edit `Config/Version.xcconfig` before each release:

```xcconfig
MARKETING_VERSION = 1.1
CURRENT_PROJECT_VERSION = 2
```

Git tags and GitHub Releases use `v$(MARKETING_VERSION)` (for example `v1.0`).

## Local git hooks

Install the pre-push version check:

```bash
./scripts/install-git-hooks.sh
```

When pushing new commits to `main`, the hook verifies that `MARKETING_VERSION` is **ahead of** the latest release tag on `origin/main`.

## Automated releases (GitHub Actions)

Pushing to **`main`** triggers `.github/workflows/release.yml`:

1. Reads `Config/Version.xcconfig`
2. Skips if tag `v<version>` already exists
3. Builds an **unsigned** `.dmg`
4. Generates release notes (user-facing + developer-facing sections)
5. Creates a GitHub Release and uploads the DMG

GitHub provides `GITHUB_TOKEN` automatically for creating releases.

Maintainer-only setup (repository secrets, local note generation): see **`docs/RELEASE.local.md`** — that file is gitignored and not published with the repo.

## Installing unsigned builds

Release DMGs are **unsigned**. Users may need to:

1. Open the DMG and drag **Cue** to Applications
2. First launch: **right-click → Open**, or allow in **System Settings → Privacy & Security**

Mention this in release notes for non-developer users.

## Manual local release smoke test

```bash
./scripts/build-release.sh
```

Output: `dist/Cue-<version>.dmg`

## Release checklist

1. Bump `Config/Version.xcconfig`
2. Merge or push to `main`
3. Confirm GitHub Actions **Release** workflow succeeded
4. Verify the release page and DMG on GitHub
5. Smoke-test install on a clean Mac
