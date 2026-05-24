# Build & install

## Install from a release

Download the latest `.dmg` from [GitHub Releases](https://github.com/tommyjtl/cue-macos/releases). Open it and drag **Cue** to Applications.

Unsigned builds may require **right-click → Open** on first launch.

The app is a menu-bar utility (no Dock icon). Use the text-cursor icon in the menu bar to open the app or change settings.

## Requirements

### macOS

- macOS **15.5+** (see `MACOSX_DEPLOYMENT_TARGET` in `Config/Shared.xcconfig`)
- Xcode **16+** to build from source

### Local mode (Ollama)

1. Install [Ollama](https://ollama.com)
2. Pull a model — the default configuration expects `gemma4:latest`:

   ```bash
   ollama pull gemma4:latest
   ```

3. Make sure Ollama is running (`http://localhost:11434`)

### Cloud mode (OpenAI)

- Supply your own **OpenAI API key** in Settings → Conversation
- Default model: `gpt-5.4` (configurable in Settings)

### Permissions

Cue needs **Screen Recording** and **Accessibility** to capture screenshots and read selected text from other apps. Grant both when prompted during onboarding or in **System Settings → Privacy & Security**.

## Build from source

```bash
git clone git@github.com:tommyjtl/cue-macos.git
cd cue-macos
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Edit Config/Local.xcconfig and set DEVELOPMENT_TEAM to your Apple Developer team ID
open Cue.xcodeproj
```

In Xcode: select the **Cue** scheme → **Run** (⌘R).

Signing settings live in `Config/Shared.xcconfig` (committed) and `Config/Local.xcconfig` (gitignored). Copy the example file before your first build.

### Project layout

```
Cue/                  Application source
Config/               Shared and local Xcode build settings (signing, version)
docs/                 Release documentation
scripts/              Release build scripts and git hooks
Cue.xcodeproj/        Xcode project
CueTests/             Unit tests
CueUITests/           UI tests
```

Maintainers: see [docs/RELEASE.md](./docs/RELEASE.md) for automated releases.

## Browser extension (Chromium)

To send the current web page as context from Chrome, Arc, Brave, or Edge:

1. Enable **Developer mode** on your browser's extensions page
2. Install the extension from **[cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension)** (releases will be published there; repo migration in progress)
3. Keep **Cue running** — the app listens on `127.0.0.1:52473` for page payloads from the extension
