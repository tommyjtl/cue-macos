# `/search` implementation plan (v0 prototype)

**Branch:** `feat/agentic-search-bookmarks` — prototypes only; not shipping in the main app release until validated.

Search saved notes from the Cue composer: user asks a question, Cue chat shows a short excerpt answer and **Open in Obsidian** links per source note.

---

## Locked decisions (v0)

| Decision | Choice |
|----------|--------|
| Corpus | **Mark export folder only** (same path as Settings → Commands → Mark) |
| Cue binary | **Pure Swift** — no Python, LanceDB, or agent runtime inside the app |
| Retrieval UX | Agentic RAG — excerpt answer + links, never a raw hit list |
| LLM for agent loop | **User's existing provider** — Private (Ollama) or Cloud (OpenAI); sidecar orchestrates, does not replace Chat settings |
| Vector store | [LanceDB](https://github.com/lancedb/lancedb) embedded in Python sidecar |
| API | Dedicated `POST /v1/search` (Option B) |

---

## Architecture: sidecar as orchestration layer

The Python backend is **not** a third chat mode. It sits **between** Cue and whichever LLM the user already configured in **Settings → Chat**.

```
┌──────────────────────────────────────────────────────────────────┐
│  Cue.app                                                         │
│  Settings → Chat: Private (Ollama) OR Cloud (OpenAI)  ◄── user │
│  Settings → Chat: Agent mode ON (prototype toggle)               │
│                                                                  │
│  /search query ──► SearchService ──► cue-search sidecar          │
│                         │ passes provider snapshot:              │
│                         │   provider, base_url, model, api_key   │
│                         │   corpus_root (mark folder)            │
└─────────────────────────┼────────────────────────────────────────┘
                          │ localhost :8765
┌─────────────────────────▼────────────────────────────────────────┐
│  cue-search (Python) — orchestration only                          │
│                                                                  │
│  ┌──────────┐   ┌──────────┐   ┌─────────────────────────────┐ │
│  │ Indexer  │──►│ LanceDB  │◄──│ Agent loop (tools)          │ │
│  │ + embed  │   │ hybrid   │   │ LLM ◄── Ollama OR OpenAI    │ │
│  └──────────┘   └──────────┘   │         (from Cue settings)  │ │
│       ▲                        └─────────────────────────────┘ │
│       │ embed via Ollama (local, separate from chat model)       │
└───────┼──────────────────────────────────────────────────────────┘
        │ read .md only
┌───────▼──────────────┐
│ Mark export folder   │
│ {date}/{title}.md    │
└──────────────────────┘
```

### What the sidecar does vs does not do

| Does | Does not |
|------|----------|
| Index mark-folder markdown into LanceDB | Replace Private / Cloud mode for normal chat |
| Run agent tool loop (`search_notes`, `read_note`) | Choose the LLM — Cue sends the active provider config |
| Call Ollama or OpenAI using **passed-in** credentials | Require a separate "search model" setting (v0) |
| Return `{ answer, sources[] }` for Cue UI | Expose raw retrieval results to the user |

### Request contract (provider pass-through)

Cue sends the active Chat configuration on every `/search` request so the sidecar never maintains its own LLM preferences.

```http
POST /v1/search
Content-Type: application/json

{
  "query": "what did I save about MLX agents?",
  "corpus_root": "/Users/…/mark-exports",
  "llm": {
    "provider": "ollama",
    "base_url": "http://localhost:11434",
    "model": "gemma4:e4b-mlx",
    "api_key": ""
  },
  "max_sources": 5
}
```

Cloud example: `"provider": "openai"`, `"base_url": "https://api.openai.com/v1"`, `"model": "gpt-5.4"`, `"api_key": "…"`.

The sidecar uses `llm.*` only for the **agent synthesis loop**. Embeddings for indexing are configured separately (see Embeddings below) and default to local Ollama so note text never leaves the machine during indexing.

---

## Sidecar distribution — what that means

"Distribution" = **how the Python process gets onto the user's Mac and stays running**. Three levels:

| Level | v0 prototype | Later |
|-------|--------------|-------|
| **Dev** | Developer runs `uv run cue-search` in a terminal; Cue expects `http://127.0.0.1:8765` | — |
| **User-assisted** | README + Settings footnote: "Start cue-search before using /search" | `make search-dev` script in repo |
| **Bundled** | Out of scope for prototype | Signed helper app or launchd agent inside DMG; auto-start when Agent mode is on |

**v0 prototype uses Dev only.** Cue shows a clear error if `GET /health` fails ("Start cue-search — see docs/search-implementation-plan.md").

---

## Embeddings

### Can we use local [Gemini Embedding 2](https://deepmind.google/models/gemini/embedding/)?

**No — not locally today.** Gemini Embedding 2 is a **cloud API** model (Gemini API / Vertex AI). It is multimodal (text, image, video, audio) and state-of-the-art for cross-modal retrieval, but it does not run on-device and is **not** available in Ollama.

### Ollama options (recommended for v0 indexing)

Ollama exposes `POST /api/embed` for local embedding models. Good fits for markdown note RAG:

| Model | Size | Dims | Notes |
|-------|------|------|-------|
| `nomic-embed-text` | ~274 MB | 768 | Default v0 pick — small, 8K context, strong baseline |
| `mxbai-embed-large` | ~670 MB | 1024 | Better accuracy, 512 token context |
| `qwen3-embedding:4b` | ~2.5 GB | up to 4096 | Highest local quality if hardware allows |

Also on Ollama: `embeddinggemma` (Google's open **Gemma** embedding family — related to but **not** Gemini Embedding 2).

**v0 default:** `nomic-embed-text` via Ollama at the same `base_url` as Private mode (typically `localhost:11434`). Indexing runs locally regardless of whether the user later chooses Cloud for the agent LLM.

### Optional later: cloud embeddings

When the user is in Cloud mode, we *could* optionally call Gemini Embedding 2 or OpenAI embeddings for indexing — only if we add an explicit setting. **Not v0** — keeps mark notes off third-party APIs by default.

---

## Vector store: LanceDB

Index location:

```
~/Library/Application Support/Cue/search/
  lancedb/
  indexer-state.json
```

- Chunk on `##` headings; ~400–800 tokens per chunk.
- [Hybrid search](https://docs.lancedb.com/search/hybrid-search) (vector + FTS) inside `search_notes` tool — internal only, not shown in UI.
- Incremental sync on mtime; full rebuild from Settings or CLI.

---

## Python package: `cue-search/`

```
cue-search/
  pyproject.toml
  README.md
  cue_search/
    main.py           # FastAPI + /health, /v1/search, /v1/index/*
    config.py         # server port, lancedb path, default embed model
    indexer.py
    store.py          # LanceDB
    embeddings.py     # Ollama /api/embed client
    agent/
      loop.py
      tools.py        # search_notes, read_note
      prompts.py
    llm/
      ollama.py       # tool-calling chat
      openai.py       # tool-calling chat (same tool schema)
```

**Sandbox:** all paths under `corpus_root` (mark folder); reject traversal.

---

## Cue integration (prototype)

### 1. Agent mode toggle (Settings → Chat)

Prototype UI placement — **below** the "Choose a model to chat with" card, **above** Private / Cloud configuration sections:

```
┌─────────────────────────────────────────────────┐
│ Choose a model to chat with          [Private ▼]│
│ Private mode runs models locally…               │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│ Agent mode                           [toggle]   │
│ Search notes with /search via local cue-search  │
│ sidecar. Uses your Private or Cloud model above.│
│ Sidecar URL: http://127.0.0.1:8765              │
└─────────────────────────────────────────────────┘
│ PRIVATE MODE (ACTIVE)                           │
│ … existing Ollama fields …                      │
```

**Behavior when Agent mode is ON:**

- `/search` is enabled (requires mark folder + sidecar healthy).
- Normal chat (`/search` aside) **unchanged** — still uses Private or Cloud directly, same as today.
- Agent mode does **not** disable or hide Private / Cloud settings.

**Behavior when Agent mode is OFF:**

- `/search` returns a Settings hint (or command disabled).

Store in `SearchConfiguration` / `AppModel`:

```swift
struct SearchConfiguration: Codable {
    var isAgentModeEnabled: Bool
    var sidecarBaseURL: String   // default http://127.0.0.1:8765
}
```

Corpus path = `MarkExportConfiguration.exportFolderPath` (no separate picker in v0).

### 2. `/search` command flow

| Piece | Role |
|-------|------|
| `SearchCommand` | Parse `/search …` |
| `SearchService` | Build request with `ConversationConfiguration` snapshot → `POST /v1/search` |
| `ConversationCoordinator` | Branch like `/mark`; render answer + `OpenObsidianNoteButton` per source |
| Settings → Commands | Optional: enable `/search` keyword (or gated purely on Agent mode) |

### 3. Chat UI (branch context)

Current branch merges `main` including the new **Settings → Chat** layout (`ChatSettingsView` with active-mode picker and split Private / Cloud sections). Agent mode toggle slots into that layout without replacing provider configuration.

---

## Phased delivery (prototype branch)

### Phase 0 — Sidecar spike

- [ ] `cue-search` skeleton, `GET /health`
- [ ] Index sample marks → LanceDB + Ollama `nomic-embed-text`
- [ ] CLI: query → answer + paths (Ollama agent LLM)

### Phase 1 — Sidecar API

- [ ] `POST /v1/search` with provider pass-through (Ollama + OpenAI)
- [ ] `POST /v1/index/rebuild`, `POST /v1/index/sync`
- [ ] Corpus sandbox tests

### Phase 2 — Cue prototype UI

- [ ] Agent mode toggle in `ChatSettingsView`
- [ ] `SearchCommand` + coordinator wiring
- [ ] `SearchService` HTTP client
- [ ] Chat: excerpt + Obsidian buttons per source
- [ ] Health check + error copy when sidecar down

### Phase 3 — Polish (still prototype)

- [ ] Index sync hook after `/mark` write
- [ ] Index stats in Settings (chunk count, last sync)
- [ ] Evaluate bundled sidecar distribution

---

## Configuration

**Sidecar defaults (`cue-search` config or env)**

```toml
[server]
host = "127.0.0.1"
port = 8765

[lancedb]
path = "~/Library/Application Support/Cue/search/lancedb"

[embeddings]
provider = "ollama"
base_url = "http://localhost:11434"
model = "nomic-embed-text"

[agent]
max_turns = 4
```

`llm.*` is **not** in sidecar config for v0 — always supplied per-request from Cue.

---

## Open questions (remaining)

1. **Agent mode + normal chat:** v0 keeps them separate (`/search` only). Future: could route other commands through sidecar — out of scope now.
2. **Tool-capable models:** Cloud search requires a model that supports function calling (OpenAI yes; Ollama model must support tools — e.g. user's `gemma4:e4b-mlx` needs verification).
3. **`/mark` dedup:** duplicate mark files pollute retrieval until write-model is resolved (`TODO.md`).
4. **Streaming:** v0 non-streaming `POST /v1/search`; add SSE later if needed.

---

## Success criteria (v0 prototype)

- Mark folder configured; `cue-search` running locally.
- Agent mode ON in Settings → Chat; Private or Cloud model selected.
- `/search what did I save about MLX?` → excerpt answer in chat + Obsidian open buttons.
- Switching Private ↔ Cloud changes which LLM the sidecar calls; embeddings stay local.
- Fully offline path works (Ollama embed + Ollama agent LLM).
- No Python inside Cue.app.

---

## References

- [LanceDB](https://github.com/lancedb/lancedb) · [quickstart](https://docs.lancedb.com/quickstart) · [hybrid search](https://docs.lancedb.com/search/hybrid-search)
- [Gemini Embedding 2](https://deepmind.google/models/gemini/embedding/) — cloud API only; not Ollama
- [Ollama embedding models](https://www.morphllm.com/ollama-embedding-models) — local alternatives
- Cue: `ChatSettingsView`, `ConversationService` tool loop, `MarkExportConfiguration`
