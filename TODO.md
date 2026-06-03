# Backlog

Linear-style tickets: **title** = problem or outcome; body = scope. Two lanes only — **Bugs** (broken today) and **Features** (not yet built). Reorder within a lane as priorities firm up; no priority field.

---

## Bugs

- [ ] **Local threads drop prior context in Ollama mode** — Verify whether the latest turn still sees all earlier messages and attachments in a local/private thread.
- [ ] **Chat layout triggers geometry cycling warnings** — Console spam: `Geometry action is cycling between duplicate values.` Likely SwiftUI feedback during LLM response rendering; investigate layout loops in the overlay chat UI.
- [ ] **Cloud mode cannot reliably use the web** — API chat is not dependably connected for live lookups: weak cross-turn memory for URLs/search, web toggles present but behavior inconsistent. Harden Responses API + web tools (overlaps feature work on cloud browsing).

---

## Features

### Overlay & chat

- [ ] **Pin overlay chat to a fixed monitor position** — Optional desktop-anchored chat instead of cursor-follow or ad hoc drag only.
- [ ] **Show short answers first, expand to full** — Brief reply in overlay first; offer expand for long generations. Pair with optional default brevity system prompt.
- [ ] **Copy and regenerate chat messages** — Copy assistant/user content; re-run the last assistant turn without retyping.
- [ ] **Remove one context item without clearing the stack** — Detach a single attachment from composer/context UI.
- [ ] **Continue a saved thread with fresh capture** — Resume conversations from desktop/history while adding new screenshot, page, or selection mid-thread. Includes: hotkey to load most recent chat; capture shortcuts attach to composer when chat is open (no forced switch to context stack).

### Context & capture

- [ ] **Capture a specific application window** — Click-to-select one window; today click-without-drag is full display and drag is region-only.
- [ ] **Structured web page context from the browser extension** — App: HTML → structured markdown for extension payloads. Extension: structured export aligned with app. Follow-on: strategy for images and other non-text page assets.

### Bookmarks & notes

- [x] **Export chat context to Obsidian with `/note`** — `/note` or `/notes` in composer writes structured markdown to a user-chosen folder under `{folder}/{yyyy-MM-dd}/`. <mark>May 30, 2026</mark>
- [ ] **Quick-save web pages with `//` in the composer** — When web-page context is present (e.g. extension push via `BrowserWebServer`), typing `//` bookmarks URL + page content—no `/bookmark` command. User-configured export folder (mirror `/note` Settings validation; TBD shared vs dedicated path). Broader: save/bookmark full sessions or context bundles for multi-day workflows. <mark>Jun 2, 2026</mark>
- [ ] **Daily digest with review and Obsidian export** — End-of-day (or on-demand) local summary of conversations, topics, and notable context; in-app review (edit/pin/discard); export markdown with frontmatter to a vault folder; optional templates (Learned / Decisions / Follow-ups / References). <mark>May 25, 2026</mark>

### AI & search

- [ ] **Lightweight Google Search in context** — Sometimes faster than asking the model; explore direct search alongside attached context.

### Shortcuts & actions

- [ ] **Canned prompt hotkeys** — e.g. `⌃1` grammar fix, `⌃2` screenshot→code, `⌃3` translate selection (EN→中文) using attached text/context.
- [ ] **Installable shortcut apps (widget library)** — User-defined or downloadable mini-apps exposing toggleable quick actions beyond built-ins. <mark>May 25, 2026</mark>

### Read aloud

- [ ] **On-device read-aloud for selected text** — Shortcut reads selection without opening chat; Supertonic ([repo](https://github.com/supertone-inc/supertonic)) evaluation (Swift/ONNX vs `supertonic serve` sidecar), model download, GPU, cold start; Settings for voice, language, speed; exploratory language-learning mode (slow-read, repeat phrase). <mark>May 25, 2026</mark>

### Data & backup

- [ ] **Settings → Data: export and import conversation history** — New **Data** sidebar item under App Settings (between General and Debug). **On disk today:** `~/Library/Application Support/Cue/` — `cue.sqlite` (threads/messages), `conversation-attachments/` (message images), `screenshots/` (optional in backup). Xcode rebuilds do not delete this folder; data is lost if the folder is removed, bundle ID changes, or `ConversationStore` fails to open. **v1:** Export All → `.cuebackup` zip (manifest version + sqlite + attachments); Reveal in Finder; footnote with path. **v2:** Import (merge vs replace TBD). Out of scope for v1 unless explicit: UserDefaults (shortcuts, API keys, Obsidian path). Recents already has per-conversation JSON export (`ConversationExport`)—Data is full-library backup/restore. <mark>Jun 2, 2026</mark>

### Onboarding

- [ ] **First-run onboarding for permissions and product usage** — Clear Screen Recording + Accessibility path with retry and System Settings deep links; in-app usage walkthrough (capture, chat, shortcuts)—today only README/website and permission-only `OnboardingView`.

### Exploratory

- [ ] **Privacy-preserving usage research** — Whether and how to measure behavior; aggregate patterns (context types, session length) without compromising privacy.

### Shipped

- [x] **Rename Private vs Cloud mode in UI** — "Private mode" (local/Ollama) vs "Cloud mode" (OpenAI), not provider names in copy.
- [x] **Move Chromium extension to dedicated repo** — [cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension); port `52473` / `127.0.0.1` kept in sync with `BrowserWebServer.swift`.

---

## How to add tickets

1. Pick **Bugs** or **Features** (and a `###` group if one fits).
2. One outcome per line: `**Title as the problem/outcome**` — scope, acceptance hints, links.
3. Merge duplicates instead of scattering the same work across groups.
4. New ideas: append `<mark>Mon DD, YYYY</mark>` at end of line. Move finished work to **Shipped** with `[x]`.
