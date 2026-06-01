# Todo List

Organized by product area. Items are not prioritized — reorder as the roadmap firms up.

---

## Bugs

Things that are broken or unreliable today.

- [ ] **Local mode context continuity** — In Ollama/local mode, does the latest message see all previous attachments and messages in the thread?
- [ ] **Geometry action cycling** — Console spam: `Geometry action is cycling between duplicate values.` Likely tied to LLM response rendering in the chat UI; investigate SwiftUI layout feedback loops.
- [ ] **OpenAI web access** — API-based chat is not reliably connected to the internet. No memory across turns for live lookups; cannot fetch URL content or search the web for up-to-date answers despite model selection. Web search toggles exist but behavior needs hardening.

---

## Overlay & chat

The cursor-anchored context stack and chat composer.

- [ ] **Pin chat on desktop** — Optional fixed position on a monitor; chat stays put instead of following the cursor or only being draggable ad hoc.
- [ ] **Short answer → long answer** — Show a brief reply in the overlay first, then offer or expand to the full response. Current answers can be very long and slow to render.
- [ ] **Brevity prompt** — Default or optional system prompt to keep responses concise.
- [ ] **Copy button** — Copy assistant (and/or user) message content from the chat UI.
- [ ] **Regenerate response** — Re-run the last turn without retyping the prompt.
- [ ] **Remove context from chat UI** — Option to detach a context item from the composer/context area without clearing the whole stack.
- [ ] **Resume conversation from desktop** — Better flow for continuing a saved thread when new context (screenshot, page, selection) needs to be added mid-conversation. See also **Attach while chat is open** under Shortcuts.

---

## Context & capture

How context enters Cue — screenshots, text, web pages, and future structured exports.

- [ ] **Application window capture** — Capture a specific app window (e.g. click-to-select). Today: click without dragging captures the full display; drag selects a region. Per-window capture is not supported yet.
- [ ] **Web page as structured context** — HTML → structured markdown for browser extension payloads.
- [ ] **Structured page export** — Browser extension side of structured context (see above).
- [ ] **Non-text web content** — Strategy for images and other non-serializable page assets in context.
- [ ] **Bookmarking** — Save/bookmark sessions or context bundles (motivated by real multi-session workflows).

---

## AI & providers

Model selection, web tools, and provider behavior.

- [ ] **Google Search integration** — Sometimes a direct web search is faster than asking the LLM; explore lightweight search-in-context.
- [ ] **OpenAI web search / browsing** — Full support for current information via Responses API + web tools (see OpenAI web access bug above).

---

## Notes & memory

Turn daily Cue usage into durable notes — a primary product direction.

- [ ] **Daily digest** — At end of day (or on demand), summarize the user's local conversations: topics covered, things learned, open questions, and notable context (pages, screenshots, selections). Runs locally in Private mode when possible. <mark>May 25, 2026</mark>
- [ ] **Digest review UI** — Surface the daily summary in the main app; let users edit, pin, or discard before saving. <mark>May 25, 2026</mark>
- [ ] **Export to Obsidian** — Write digests (and optionally full threads) as Markdown with frontmatter into a user-chosen vault folder. Consider wikilinks for recurring topics. <mark>May 25, 2026</mark>
- [x] **Inline /note export** — `/note` or `/notes` in the overlay composer writes a structured markdown note into a user-chosen Obsidian folder under `{folder}/{yyyy-MM-dd}/`. <mark>May 30, 2026</mark>
- [ ] **Note templates** — Optional structure for digests (e.g. "Learned / Decisions / Follow-ups / References") so exports are useful in any PKM tool, not only Obsidian. <mark>May 25, 2026</mark>

---

## Read aloud & language learning

On-device text-to-speech for selected text — user-requested 点读机-style flow. Candidate engine: [Supertonic](https://github.com/supertone-inc/supertonic) (ON-device, multilingual, Swift/ONNX/`supertonic serve`).

- [ ] **Read selection shortcut** — After selecting text anywhere, a dedicated shortcut reads it aloud without opening chat. Preconfigure language, speed, and voice in Settings. <mark>May 25, 2026</mark>
- [ ] **Supertonic integration** — Evaluate native Swift/ONNX vs local HTTP sidecar (`supertonic serve`); handle model download, GPU acceleration, and cold-start latency. <mark>May 25, 2026</mark>
- [ ] **TTS settings** — Voice style, language (`lang` or `na`), speed, and quality steps; persist per user. <mark>May 25, 2026</mark>
- [ ] **Language-learning mode (exploratory)** — Slow-read, repeat phrase, or read attached context in a target language. Builds on selection capture + on-device TTS without sending text to the cloud. <mark>May 25, 2026</mark>

---

## Shortcuts

Global hotkeys and power-user flows.

- [ ] **Attach while chat is open** — When the overlay is in chat mode, action shortcuts (screenshot capture, selection, browser page, clipboard) add attachments directly to the chat composer; do not switch to the context stack panel.
- [ ] **Prompt shortcuts** — Send canned prompts without typing, e.g.:
  - `⌃1` — Fix grammar (selected text or context)
  - `⌃2` — Transcribe screenshot into code
  - `⌃3` — Translate selection (e.g. English → 中文) using attached text or context
- [ ] **Shortcut apps (widgets)** — Let users install or define mini-apps inside Cue; each app exposes one or more quick shortcuts (grammar, transcribe, translate, etc.) that can be toggled on/off. Foundation for a small library of downloadable actions beyond built-in prompts. <mark>May 25, 2026</mark>
- [ ] **Quick load recent chat** — Keyboard shortcut to restore the most recent conversation into the overlay.

---

## Onboarding

First-run experience — permissions and product usage.

- [ ] **Usage onboarding** — Interactive in-app walkthrough (animated or step-by-step) that teaches how to capture context, open chat, and use shortcuts. Today usage guidance lives on the website / README only; `OnboardingView` handles permissions but not product usage.
- [ ] **Permission onboarding** — Clearer first-run path for Screen Recording and Accessibility, with retry and deep links to System Settings.

---

## Research & analytics (exploratory)

- [ ] **Behavior tracking** — How (if at all) should usage be measured in a research prototype?
- [ ] **Distribution / clustering** — Can aggregate patterns (e.g. context types, session length) inform product decisions without compromising privacy?

---

## Done

- [x] **Rename modes** — "Private mode" (local/Ollama) vs "Cloud mode" (OpenAI) instead of provider names in UI copy.
- [x] **Migrate extension repo** — Extension lives at [cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension); port `52473` and `127.0.0.1` stay in sync with `BrowserWebServer.swift`.

---

## Notes

_Add new items under the most relevant section. Move shipped work to **Done**. When adding a new item, append the idea date at the end of the line as `<mark>Mon DD, YYYY</mark>` (yellow highlight). Only tag items added on or after the date they were introduced — leave older backlog items untagged._
