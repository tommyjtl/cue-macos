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
- [ ] **Ambient screen grounding on invoke (cursor-centric capture)** — With Ziang: attach rich desktop context when invoking Cue without changing workflow—"sharing ground" so user and model refer to the same on-screen places ("point here and there"). **User-model representation (exploratory):** lightweight local trace of cursor path, key activity, and repeated framing of screen regions leading up to invoke; later gaze + cursor fusion ([PyGaze](https://www.pygaze.org)). **AX tree complement:** macOS Accessibility (`AXUIElement`) exposes a semantic UI tree—roles, labels, text, bounds, focus—not DOM/CSS; `AXUIElementCopyElementAtPosition` can ground cursor to controls (quality varies; canvas/custom UIs often sparse). Browsers surface a web a11y tree; structured page export via extension may still be richer. Cue has `AccessibilityClient` for cross-app permission checks only today. **Phased build:** (1) on first capture in a session, also grab full-screen (or display) context—not only drag-region or bare-click full display; (2) on invoke, attach cursor coordinates + recent pointer history with that screen context; (3) optional eye-tracking pointer layered on cursor movement. **Open:** privacy/retention, token budget vs smart cropping around cursor, Accessibility + Screen Recording scope, what stays on-device vs ships to cloud models. Ref: [design thread](https://chatgpt.com/c/6a261f5e-0794-83e8-b0d3-5d2514158730). <mark>Jun 8, 2026</mark>

### Bookmarks & notes

- [x] **Export chat context with `/save`** — `/save` exports conversation JSON via save dialog (same as Recents → Export JSON). Settings → Commands (toggle + optional default folder). <mark>Jun 4, 2026</mark>
- [x] **Mark pages with `/mark` and `//`** — Bookmarks oldest page in session; separate export folder; `{title}.md`. `//` is a quick alias. Settings → Commands. <mark>Jun 4, 2026</mark>
- [ ] **Quote attached selection in `/mark` bookmarks** — Double-⌘C selection already lands in context (`Selected text from …`) and counts toward `hasUsableContext`, but `MarkExportPrompts.defaultBase` never tells the model the paste is likely what the user wanted to highlight. Explore prompt/body rules: when selection is substantive, surface it in the note—e.g. a blockquote or callout in or near `## Highlights`—without dumping the full excerpt when it's long. Open questions: overlap with YouTube default-synthesis instruction; respect explicit user hint over auto-quote; skip when selection is trivial or redundant with page text. <mark>Jun 7, 2026</mark>
- [ ] **`/mark` write model: one note per conversation vs always new file** — Today each `//` or `/mark` always writes a new `{title}.md` under the date folder (collision suffix `-2`, `-3`, …); no append-to-thread behavior. **Always-new pros:** simple mental model; user may not curate vault manually; future agents (`/search`, digest) could merge/dedupe. **Always-new cons (likely heavier):** repeated titles for the same page/session; duplicated Highlights and source metadata; vault clutter grows fast. **Alternatives to research:** one canonical note per conversation thread (append sections or refresh in place); one note per primary URL (update `## Highlights` / `## My notes` on re-mark); explicit "new angle" only when user hint differs. Leaning: duplication cost probably outweighs agent-cleanup convenience—decide before scaling mark volume. <mark>Jun 9, 2026</mark>
- [ ] **Daily digest with review and Obsidian export** — End-of-day (or on-demand) local summary of conversations, topics, and notable context; in-app review (edit/pin/discard); export markdown with frontmatter to a vault folder; optional templates (Learned / Decisions / Follow-ups / References). <mark>May 25, 2026</mark>

### AI & search

- [ ] **`/search` over saved notes (v0)** — Excerpt answer + **Open in Obsidian** per source. Cue stays pure Swift; Python sidecar (`cue-search`) runs agentic RAG over mark folder; [LanceDB](https://github.com/lancedb/lancedb) index; dedicated `POST /v1/search` API. Plan: [docs/search-implementation-plan.md](docs/search-implementation-plan.md). <mark>Jun 9, 2026</mark>
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

- [ ] **Cue Mobile: local capture sidecar (iOS/Android)** — Desktop Cue stays the workspace; mobile is **intake**, not a full chat clone—Siri/Gemini already own ambient search on phone. **Problem:** quick saves while browsing (great article, screenshot, link) with no cloud account. **Entry:** system share sheet → Cue Mobile (URL and/or screenshot + optional user hint). **On device:** queue captures locally; optional on-device model (Apple Intelligence / Gemini Nano / etc.) drafts a note—same artifact shape as desktop `/mark` (`{yyyy-MM-dd}/{title}.md`, `## Highlights`, `## Why I saved this`, `## My notes`; `ObsidianNoteWriter` / `MarkExportPrompts` vocabulary) so synced files land in the mark export folder and feed `/search` without a second corpus. **Sync (no account):** manual first—AirDrop or same-LAN transfer (Multipeer / Bonjour / mDNS); bundle format akin to planned `.cuebackup` (manifest + markdown + image attachments); desktop **Import captures** into mark folder; automatic background sync later. **Open:** stub captures (`pending` URL/image) enriched on desktop vs full generation on phone; duplicate URL handling (overlaps `/mark` write-model ticket); React Native vs SwiftUI-first (share extensions need native shells either way). **Defer:** mobile chat composer and on-device `/search`—search stays on desktop/sidecar until v0 is stable. **Phased:** (0) spec + bundle format, (1) share → local queue → stub/full note, (2) LAN/AirDrop import on desktop, (3) optional mobile search over synced vault. <mark>Jun 10, 2026</mark>

### Shipped

- [x] **Rename Private vs Cloud mode in UI** — "Private mode" (local/Ollama) vs "Cloud mode" (OpenAI), not provider names in copy.
- [x] **Move Chromium extension to dedicated repo** — [cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension); port `52473` / `127.0.0.1` kept in sync with `BrowserWebServer.swift`.

---

## How to add tickets

1. Pick **Bugs** or **Features** (and a `###` group if one fits).
2. One outcome per line: `**Title as the problem/outcome**` — scope, acceptance hints, links.
3. Merge duplicates instead of scattering the same work across groups.
4. New ideas: append `<mark>Mon DD, YYYY</mark>` at end of line. Move finished work to **Shipped** with `[x]`.
