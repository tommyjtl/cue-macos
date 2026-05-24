# Cue (macOS)

<p align="center">
  <img src="Design/logo-icns.png" alt="Cue app icon" width="256">
</p>

A menu-bar utility for capturing context — screenshots, selected text, browser pages — and chatting with an AI from a lightweight overlay near your cursor.

> 🚨 **Experimental software.** Cue is an HCI/UX research prototype. Expect rough edges, incomplete flows, and bugs. Use it cautiously and don't rely on it for anything critical.

## What it does

- Lives in the menu bar and runs a cursor-anchored context overlay
- Captures screenshots, selected text, and web pages as context for a conversation
- Sends prompts to a **local model** (Ollama) or a **cloud model** (OpenAI)
- Keeps a local conversation history on disk

**Install or build from source:** see [BUILD.md](./BUILD.md).

## Basic usage

| Action | Default shortcut |
|---|---|
| Add to context (selected text or screenshot) | Double **Option** |
| Open chat composer | Double **Shift** |
| Dismiss overlay / clear context | **Escape** |

Shortcuts are configurable in **Settings → Shortcuts**.

### Menu bar

- **Open App** — main window
- **Provider** — quick switch between Ollama and OpenAI
- **Settings** — permissions, shortcuts, model configuration
- **Quit Cue**

See [TODO.md](./TODO.md) for planned work and known issues.

## Contributing

Forks and questions are welcome.

- **Issues:** [github.com/tommyjtl/cue-macos/issues](https://github.com/tommyjtl/cue-macos/issues)
- **Browser extension:** [github.com/tommyjtl/cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension)

## License

[MIT](./LICENSE) — Copyright (c) 2026 Tommy
