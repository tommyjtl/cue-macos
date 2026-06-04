# Composer commands

## Commands

| Command | Aliases | Intent |
|---------|---------|--------|
| `/save` | `/note`, `/notes` | Structured summary of the conversation |
| `/mark` | `//` | Bookmark the **oldest page** in the session |

## Settings

**Settings → Commands** — separate enable toggles, export folders, and system prompts for Save and Mark.

Legacy Obsidian settings under General were moved here. Save settings migrate from `obsidian-export-configuration` UserDefaults.

## Export layout

- **Save:** `{saveFolder}/{yyyy-MM-dd}/{title}.md` — all session URLs in `## References` (unchanged).
- **Mark:** `{markFolder}/{yyyy-MM-dd}/{title}--{domain}.md` — primary page only; no multi-URL References section. `## Why I saved this` and `## My angle` are omitted unless hint or conversation provides real content (lean `## What stood out` otherwise).

## Implementation

- `ComposerCommandRegistry` — parse and composer highlighting
- `SaveExportService` / `MarkExportService` — LLM + `ObsidianNoteWriter` with `ExportKind`
