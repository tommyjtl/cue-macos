# Releasing Cue

## Version source of truth

Edit `Config/Version.xcconfig` before each release:

```xcconfig
MARKETING_VERSION = 1.1
CURRENT_PROJECT_VERSION = 2
```

Git tags and GitHub Releases use `v$(MARKETING_VERSION)` (for example `v1.0`).

## Create a release (GitHub Actions)

Releases are **manual** — they do not run on every push to `main`.

1. Bump `Config/Version.xcconfig` and push to `main`
2. Configure signing secrets (see **`docs/RELEASE.local.md.example`**)
3. Open **[Actions → Release](https://github.com/tommyjtl/cue-macos/actions/workflows/release.yml)**
4. Click **Run workflow**
5. Enter the release tag (e.g. `v1.0`) — must match `MARKETING_VERSION` in `Config/Version.xcconfig`
6. Optionally turn off **Generate release notes** to publish a commit list only
7. Run on branch **`main`**

The workflow will:

1. Validate the tag (format, not already published, matches `Version.xcconfig`)
2. Import your Developer ID certificate
3. Build a **universal** (arm64 + x86_64) signed `.dmg` and notarize it
4. Generate release notes (AI by default, or a basic commit list if disabled)
5. Create a GitHub Release and upload the DMG

**Unsigned releases do not work** for Screen Recording on macOS 15+. Signing secrets are required.

Maintainer-only secret setup: copy **`docs/RELEASE.local.md.example`** to **`docs/RELEASE.local.md`** (gitignored).

## Manual local release smoke test

```bash
export RELEASE_SIGN=1
export DEVELOPMENT_TEAM=YOUR_TEAM_ID
./scripts/build-release.sh
```

Output: `dist/Cue-<version>.dmg` (universal binary)

## Release checklist

1. Bump `Config/Version.xcconfig`
2. Push to `main`
3. Confirm signing secrets are set on GitHub
4. Run the **Release** workflow with the matching tag (e.g. `v1.1`)
5. Confirm the workflow succeeded
6. Install the DMG on a clean Mac and verify Screen Recording + Accessibility
7. Verify the release page and DMG on GitHub
