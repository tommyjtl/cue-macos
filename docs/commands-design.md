# Composer commands

## Commands

| Command | Aliases | Intent |
|---------|---------|--------|
| `/save` | `/note`, `/notes` | Export the current conversation as JSON (same as Recents → Export JSON) |
| `/mark` | `//` | Bookmark the **oldest page** in the session via LLM → markdown file |

## Settings

**Settings → Commands**

- **Save:** enable toggle; optional default folder for the save dialog only.
- **Mark:** enable toggle, export folder, system prompt.

## Export behavior

- **Save:** `NSSavePanel` → `ConversationExport.encode` (no LLM).
- **Mark:** `{markFolder}/{yyyy-MM-dd}/{title}--{domain}.md` via LLM.
