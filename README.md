# Cue (macOS)

<p align="center">
  <img src="Design/logo-icns.png" alt="Cue app icon" width="256">
</p>

A menu-bar utility for capturing context — screenshots, clipboard text, browser pages — and chatting with an AI from a lightweight overlay near your cursor.

> 🚨 **Experimental software.** Cue is an HCI/UX research prototype. Expect rough edges, incomplete flows, and bugs. Use it cautiously and don't rely on it for anything critical.

## What it does

- Lives in the menu bar and runs a cursor-anchored context overlay
- Captures screenshots, clipboard text, and web pages as context for a conversation
- Sends prompts to a **local model** (Ollama) or a **cloud model** (OpenAI)
- Keeps a local conversation history on disk

**Install or build from source:** see [BUILD.md](./BUILD.md).

## Basic usage

1. **Add context** — copy text, capture a screenshot, or push a page from the browser extension.
2. **Ask a question** — open the chat composer and send a prompt; Cue includes your attached context.
3. **Dismiss** — press Escape to hide the overlay or clear the stack.

| Action | Default shortcut |
|---|---|
| Attach clipboard text to context | Double **⌘C** (copy twice in quick succession) |
| Capture a screenshot region | Double **Option** |
| Open chat composer | Double **Shift** |
| Dismiss overlay / clear context | **Escape** |

Double **⌘C** uses whatever plain text is on the clipboard after your second copy — a single **⌘C** behaves normally and does not attach anything. Double **Option** always starts a screenshot region capture (it does not read selected text). With context already attached, double **Shift** opens a new chat; without context, it resumes your most recent conversation.

The double **Option** shortcut is configurable in **Settings → General**. Double **Shift** and double **⌘C** are fixed for now.

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
