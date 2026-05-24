# Todo List

Organized from prototype notes. Items are not prioritized — reorder as the roadmap firms up.

---

## Bugs

- [ ] **Local mode context continuity** — In Ollama/local mode, does the latest message see all previous attachments and messages in the thread?
- [ ] **Geometry action cycling** — Console spam: `Geometry action is cycling between duplicate values.` Likely tied to LLM response rendering in the chat UI; investigate SwiftUI layout feedback loops.
- [ ] **OpenAI web access** — API-based chat is not reliably connected to the internet. No memory across turns for live lookups; cannot fetch URL content or search the web for up-to-date answers despite model selection. Web search toggles exist but behavior needs hardening.

---

## Chat UI & responses

- [ ] **Short answer → long answer** — Show a brief reply in the overlay first, then offer or expand to the full response. Current answers can be very long and slow to render.
- [ ] **Brevity prompt** — Default or optional system prompt to keep responses concise.
- [ ] **Copy button** — Copy assistant (and/or user) message content from the chat UI.
- [ ] **Regenerate response** — Re-run the last turn without retyping the prompt.
- [ ] **Remove context from chat UI** — Option to detach a context item from the composer/context area without clearing the whole stack.
- [ ] **Resume conversation from desktop** — Better flow for continuing a saved thread when new context (screenshot, page, selection) needs to be added mid-conversation.

---

## Context & capture

- [ ] **Full window capture** — Capture an entire window, not only a dragged region.
- [ ] **Web page as structured context** — HTML → structured markdown for browser extension payloads.
- [ ] **Non-text web content** — Strategy for images and other non-serializable page assets in context.
- [ ] **Bookmarking** — Save/bookmark sessions or context bundles (motivated by real multi-session workflows).

---

## Providers & modes

- [ ] **Rename modes** — "Private mode" (local/Ollama) vs "Cloud mode" (OpenAI) instead of provider names in UI copy.
- [ ] **Google Search integration** — Sometimes a direct web search is faster than asking the LLM; explore lightweight search-in-context.
- [ ] **OpenAI web search / browsing** — Full support for current information via Responses API + web tools (see bug above).

---

## Shortcuts & productivity

- [ ] **Prompt shortcuts** — Send canned prompts without typing, e.g.:
  - ⌃1 — Fix grammar (selected text or context)
  - ⌃2 — Transcribe screenshot into code
- [ ] **Quick load recent chat** — Keyboard shortcut to restore the most recent conversation into the overlay.

---

## Onboarding & permissions

- [ ] **Permission onboarding** — Clearer first-run path for Screen Recording and Accessibility, with retry and deep links to System Settings.

---

## Browser extension

- [ ] **Migrate extension repo** — Publish builds at [cue-chromium-extension](https://github.com/tommyjtl/cue-chromium-extension); keep port `52473` and `127.0.0.1` in sync with `BrowserWebServer.swift`.
- [ ] **Structured page export** — See "Web page as structured context" above.

---

## Research & analytics (exploratory)

- [ ] **Behavior tracking** — How (if at all) should usage be measured in a research prototype?
- [ ] **Distribution / clustering** — Can aggregate patterns (e.g. context types, session length) inform product decisions without compromising privacy?

---

## Notes

_Add new items at the top of the relevant section. Strike through or move to a "Done" section when shipped._
