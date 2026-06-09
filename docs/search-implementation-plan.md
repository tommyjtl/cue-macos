# `/search` implementation plan

Search saved notes from the Cue composer: user asks a question, Cue chat shows a short excerpt answer and **Open in Obsidian** links per source note.

**Principles**

- **Cue stays pure** — Swift/macOS app only; no embedded agent runtime, no LanceDB, no Python inside the app bundle (v0).
- **Python sidecar** — a small local backend owns indexing, retrieval, and the agent loop.
- **Folder-scoped corpus** — search is bounded to a configured directory (mark export folder for v0).
- **Agentic RAG** — semantic retrieval narrows the haystack; an LLM agent synthesizes the answer; the user never sees raw hit lists.

Related backlog: `TODO.md` → **AI & search** → `/search` over saved notes.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Cue.app (Swift)                                            │
│  /search command → SearchService → HTTP → sidecar           │
│  Response → chat UI (excerpt + OpenObsidianNoteButton)      │
└──────────────────────────┬──────────────────────────────────┘
                           │ localhost
┌──────────────────────────▼──────────────────────────────────┐
│  cue-search (Python)                                        │
│  ┌─────────────┐   ┌──────────────┐   ┌─────────────────┐ │
│  │ Indexer     │   │ LanceDB      │   │ Agent loop      │ │
│  │ watch/chunk │──►│ hybrid search│◄──│ LLM + tools     │ │
│  │ embed       │   │ (embedded)   │   │                 │ │
│  └─────────────┘   └──────────────┘   └────────┬────────┘ │
│                                                 │          │
│                                    Ollama / OpenAI / MLX   │
└─────────────────────────────────────────────────────────────┘
                           ▲
                           │ reads only
              ┌────────────┴────────────┐
              │ Mark export folder      │
              │ {vault}/{yyyy-MM-dd}/*.md│
              └─────────────────────────┘
```

### Why a sidecar

| Concern | In Cue | In Python sidecar |
|---------|--------|-------------------|
| LanceDB + embeddings | Heavy SPM/Rust bridge | Native [Python SDK](https://docs.lancedb.com/quickstart) |
| Agent tool loop | Duplicates Ollama loop for a different toolset | Natural fit |
| Index rebuild / file watch | Extra macOS lifecycle | Standard Python tooling |
| Shipping | Keeps app binary and compile time lean | Optional dev dependency; bundle later if needed |

Hermes and other third-party agents are out of scope — we **borrow the pattern** (retrieve → tool loop → synthesize), not the dependency.

---

## Vector store: LanceDB

[LanceDB](https://github.com/lancedb/lancedb) is embedded (in-process, no separate server), local-first, and supports **vector + full-text hybrid search** — useful for note titles, tags, and conceptual queries together.

**Index location (proposed)**

```
~/Library/Application Support/Cue/search/
  lancedb/          # LanceDB dataset directory
  indexer-state.json # last scan mtime per file, schema version
```

**Table schema (per chunk)**

| Column | Type | Purpose |
|--------|------|---------|
| `id` | string | stable chunk id (`path:lineStart-lineEnd`) |
| `file_path` | string | absolute path to `.md` |
| `title` | string | from frontmatter or first line |
| `section` | string | e.g. `Highlights`, `Why I saved this` |
| `text` | string | chunk body (FTS + display) |
| `vector` | float[] | embedding |
| `source_url` | string? | frontmatter `source` |
| `modified_at` | timestamp | file mtime |

**Chunking**

- Split on markdown headings (`##` and above); keep frontmatter metadata on every chunk from that file.
- Target ~400–800 tokens per chunk; overlap one heading level where sections are short.
- Re-index: full scan on first run; incremental on file mtime change; hook from Cue after successful `/mark` write (optional v0.1).

**Embeddings (v0)**

- Prefer **local** embedder in the sidecar (e.g. `fastembed` or Ollama `/api/embeddings`) so private mode stays offline.
- Document the chosen model in config; re-embed entire table on model change.

**Retrieval**

- Default: [hybrid search](https://docs.lancedb.com/search/hybrid-search) (vector + FTS, RRF rerank).
- Exposed to the agent as `search_notes(query, limit)` — not shown directly to the user.

---

## Python backend: `cue-search`

New package in this repo (name TBD), e.g. `cue-search/`.

```
cue-search/
  pyproject.toml
  README.md
  cue_search/
    __init__.py
    main.py              # FastAPI or stdlib HTTP entry
    config.py            # corpus path, LLM endpoint, LanceDB path
    indexer.py           # scan, chunk, embed, upsert
    store.py             # LanceDB table ops + hybrid query
    agent/
      loop.py            # tool-calling loop
      tools.py           # search_notes, read_note
      prompts.py
    llm/
      client.py          # Ollama + OpenAI adapters
```

**Dependencies (initial)**

- `lancedb`
- `fastapi` + `uvicorn` (or lightweight alternative)
- embedding library (TBD)
- `httpx` for LLM APIs
- `watchdog` (optional, for folder watch)

**Sandbox**

- All file reads and index sources must resolve under the configured `corpus_root`.
- Reject `..`, symlinks escaping root, and absolute paths outside root.

---

## API shape: two options

### Option A — OpenAI-compatible chat completions

Expose `POST /v1/chat/completions` (streaming optional). Cue (or any client) sends messages; the sidecar runs the agent loop internally and returns a single assistant message.

**Pros**

- Reuse existing OpenAI client code paths in Cue for prototyping.
- Standard tooling (curl, OpenAI SDK) for debugging.

**Cons**

- No standard field for **structured sources** (file paths, excerpts). Would need conventions in message content (e.g. JSON block) or custom fields that break compatibility.
- Harder to render `OpenObsidianNoteButton` per source without fragile parsing.
- Blurs “chat with model” vs “search my notes” — two different products on one endpoint.

### Option B — Dedicated search API (recommended for v0)

Purpose-built contract for Cue.

```http
POST /v1/search
Content-Type: application/json

{
  "query": "what did I save about MLX agents?",
  "corpus_root": "/Users/…/Obsidian/…/bookmarks",
  "max_sources": 5
}
```

```json
{
  "answer": "You saved two notes about local MLX agent stacks…",
  "sources": [
    {
      "file_path": "/Users/…/2026-06-08/Local Agentic AI on Mac with MLX at WWDC26.md",
      "title": "Local Agentic AI on Mac with MLX at WWDC26",
      "excerpt": "The local stack relies on four layers: MLX → MLX LM → …",
      "section": "What stood out"
    }
  ],
  "debug": {
    "tool_calls": 3,
    "retrieval_chunks": 8
  }
}
```

Additional endpoints:

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/health` | Sidecar up, index stats |
| `POST` | `/v1/index/rebuild` | Full re-index (Settings or CLI) |
| `POST` | `/v1/index/sync` | Incremental scan |

**Pros**

- Clean mapping to Cue UI: `answer` in chat bubble, `sources[]` → `OpenObsidianNoteButton`.
- Explicit corpus boundary per request (Cue passes mark folder from settings).
- `debug` optional; strip in production UI.

**Cons**

- New Swift client (`SearchService`) — small, isolated module.

**Recommendation:** **Option B for v0.** Option A can be added later as a debug/CLI surface if useful.

---

## Agent loop (minimal)

Same pattern as Cue’s Ollama `web_search` loop, implemented in Python.

**Tools**

| Tool | Description |
|------|-------------|
| `search_notes` | Hybrid LanceDB query; returns ranked chunks with path, section, snippet |
| `read_note` | Read full file or heading subtree (path must be under `corpus_root`) |

**Flow**

1. Receive `query` + `corpus_root`.
2. Ensure index is fresh enough (sync if stale).
3. **Optional auto-retrieve:** inject top-K hybrid hits into system context (Hermes [#844](https://github.com/NousResearch/hermes-agent/issues/844) pattern).
4. Agent loop (max N turns, e.g. 4):
   - LLM may call `search_notes` / `read_note`.
   - Tool results appended to conversation.
5. Final turn: model returns structured JSON (answer + cited source paths) per sidecar schema.
6. Sidecar validates paths, fills `sources[]` excerpts from disk, returns response.

**LLM backend**

- **v0:** Ollama tool-capable model at `http://localhost:11434` (matches Cue private mode).
- **Later:** OpenAI for cloud `/search`; MLX local server per [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) / WWDC26 stack.

**System prompt highlights**

- Answer only from corpus tools; say when nothing relevant is found.
- Prefer concise excerpt-style answers.
- Cite notes by title; sidecar maps to `file_path`.

---

## Cue integration (Swift)

Mirror `/mark` and `/save` — no agent logic in the app.

### New pieces

| Piece | Responsibility |
|-------|----------------|
| `SearchCommand` | Parse `/search …` and hint text |
| `SearchExportConfiguration` | Enable toggle, sidecar URL, reuse mark folder (or separate corpus path) |
| `SearchService` | `POST /v1/search`, map response to chat message |
| `ConversationCoordinator` | Branch on `/search` like mark/save |
| Settings → Commands | Enable `/search`, sidecar URL, “Rebuild index” action |
| UI | Render `answer` + one `OpenObsidianNoteButton` per `source.file_path` |

### Chat message format

Reuse the `/mark` saved-note pattern where possible (`ObsidianSavedNoteMessage` / path embedding), extended for multiple sources:

- Assistant text = `answer`
- Structured attachment or parseable footer with source paths for buttons

### Sidecar lifecycle (v0)

- Document: user runs `uv run cue-search` (or `make search-dev`) alongside Cue.
- `GET /health` on compose open or first `/search`; show Settings hint if down.
- **Later:** launch agent via `SMJobBless` / login item / bundled helper — out of v0 scope.

---

## Phased delivery

### Phase 0 — Spike (1–2 days)

- [ ] `cue-search` package skeleton + `GET /health`
- [ ] Index 10–20 sample mark `.md` files into LanceDB
- [ ] Hybrid `search_notes` returns sensible chunks for 3 test queries
- [ ] Manual agent loop in CLI (no Cue yet)

**Exit:** demonstrate query → answer + file paths in terminal.

### Phase 1 — Sidecar v0

- [ ] `POST /v1/search` with Ollama agent loop
- [ ] Incremental indexer + `POST /v1/index/rebuild`
- [ ] Corpus sandbox tests
- [ ] Config file: `~/.cue/search.toml` or env vars

### Phase 2 — Cue v0

- [ ] `SearchCommand` + Settings → Commands
- [ ] `SearchService` HTTP client
- [ ] Coordinator wiring + status strings
- [ ] Chat UI: excerpt + Obsidian buttons per source
- [ ] Tests: command parsing, response mapping (mock sidecar)

### Phase 3 — Polish

- [ ] Trigger index sync after `/mark` write (Cue calls `/v1/index/sync`)
- [ ] Indexing progress in Settings (chunk count, last sync)
- [ ] Cloud LLM option for search-only
- [ ] Overlap with `/mark` dedup policy (one note per URL vs many duplicates)

---

## Configuration

**Cue (UserDefaults / Settings)**

```swift
struct SearchConfiguration: Codable {
    var isEnabled: Bool
    var sidecarBaseURL: String      // default http://127.0.0.1:8765
    var corpusFolderPath: String    // default: mark export folder
}
```

**Sidecar (`cue-search` config)**

```toml
[server]
host = "127.0.0.1"
port = 8765

[corpus]
# default; overridden per-request by Cue
root = ""

[lancedb]
path = "~/Library/Application Support/Cue/search/lancedb"

[embeddings]
provider = "fastembed"  # or "ollama"
model = "BAAI/bge-small-en-v1.5"

[llm]
provider = "ollama"
base_url = "http://localhost:11434"
model = "qwen3:8b"  # tool-capable; align with Cue private mode
max_agent_turns = 4
```

---

## Open questions

1. **Corpus v0:** mark export folder only, or any user-picked Obsidian vault path?
2. **Sidecar distribution:** dev-only script first, or ship a signed helper in the DMG later?
3. **Embedding model:** bundle weights vs download on first index (size vs offline)?
4. **Cloud `/search`:** allowed in v0 or private-only until MLX path is ready?
5. **`cue.sqlite` threads:** index conversation history in v1, or marks-only forever?
6. **Relation to `/mark` write model:** duplicate mark files will pollute retrieval until dedup is resolved (`TODO.md`).

---

## Success criteria (v0)

- User types `/search what did I save about MLX?` with mark folder configured and sidecar running.
- Within ~30s (local, small corpus), chat shows a **readable excerpt answer**.
- Each relevant note has an **Open in Obsidian** button that opens the correct file.
- No search hits or raw chunks shown in the UI.
- Index and query work fully offline (Ollama + local embeddings).
- Cue binary contains **no** Python, LanceDB, or agent runtime.

---

## References

- [LanceDB](https://github.com/lancedb/lancedb) — embedded retrieval, hybrid search
- [LanceDB quickstart](https://docs.lancedb.com/quickstart)
- [LanceDB hybrid search](https://docs.lancedb.com/search/hybrid-search)
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — future on-device LLM path
- [Hermes kb RAG proposal](https://github.com/NousResearch/hermes-agent/issues/844) — auto-retrieve pattern (reference only)
- Cue: `docs/commands-design.md`, `MarkExportService`, `ConversationService` Ollama tool loop
