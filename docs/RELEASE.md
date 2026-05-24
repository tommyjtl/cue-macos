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
2. Open **[Actions → Release](https://github.com/tommyjtl/cue-macos/actions/workflows/release.yml)**
3. Click **Run workflow**
4. Enter the release tag (e.g. `v1.0`) — must match `MARKETING_VERSION` in `Config/Version.xcconfig`
5. Run on branch **`main`**

The workflow will:

1. Validate the tag (format, not already published, matches `Version.xcconfig`)
2. Build an **unsigned** `.dmg`
3. Generate release notes (user-facing + developer-facing sections)
4. Create a GitHub Release and upload the DMG

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
2. Push to `main`
3. Run the **Release** workflow with the matching tag (e.g. `v1.1`)
4. Confirm the workflow succeeded
5. Verify the release page and DMG on GitHub
6. Smoke-test install on a clean Mac
