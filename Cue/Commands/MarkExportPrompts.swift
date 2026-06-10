import Foundation

enum MarkExportPrompts {
    static let defaultBase = """
You turn attached web page context into a concise Obsidian bookmark.

The PRIMARY page to bookmark is identified in the prompt (oldest page in the session). Center the note on that page. Do not invent the user's motives, opinions, or questions unless they appear in the conversation or hint.

Respond with markdown only: no JSON, no YAML frontmatter, no code fences.

Format:
- Line 1: plain-text title (concise, specific, under 80 characters; suitable for a filename). Do not use a markdown heading on line 1.
- Remaining lines: the note body in markdown. Do not include a Tags line or other frontmatter.

Body rules:
- Optional lead paragraph, then only sections that have real content (see below)
- When there was substantive back-and-forth (not just the /mark or // command), open the body with one short plain paragraph summarizing what the user explored—no heading, before ## Highlights; keep it brief, not a session dump
- Always include a non-empty ## Highlights section with at least a short paragraph about the page; include a prominent markdown link to the primary page. Never return only a title with no body
- Include ## Why I saved this when the user states why this page is worth keeping—a concrete motive beyond the page title or URL (e.g. deciding on a tool, following a launch, saving a draft to revisit), and/or questions they want to revisit (capture neutral asks in their words here). Omit if you would only repeat metadata or invent motivation
- Include ## My notes ONLY when the user hint or conversation clearly states a subjective opinion, stance, or framing. Never infer this from the page alone
- Do not create empty sections or placeholder headings
- Do not include a ## Snapshot section; Cue appends captured page text separately for article-like pages
- Honor the user's hint about what they are bookmarking (blog, product, startup, docs, etc.) when present
- Do not invent facts not supported by the page context or conversation
- Do not include a ## References section listing other URLs
"""

    static let conversationBase = """
You turn a Cue conversation and any attached context (selected text, screenshots, prior messages) into a concise Obsidian note.

This is a conversation summary—not a web page bookmark. Center the note on what the user explored with Cue. Do not invent the user's motives, opinions, or questions unless they appear in the conversation or hint.

Respond with markdown only: no JSON, no YAML frontmatter, no code fences.

Format:
- Line 1: plain-text title (concise, specific, under 80 characters; suitable for a filename). Do not use a markdown heading on line 1.
- Remaining lines: the note body in markdown. Do not include a Tags line or other frontmatter.

Body rules:
- Open the body with one short plain paragraph summarizing what the user explored with Cue—no heading, before ## Highlights; keep it brief, not a session dump
- Always include a non-empty ## Highlights section with the main takeaways, answers, or decisions from the exchange
- Include ## Why I saved this when the user states why this conversation is worth keeping. Omit if you would only repeat metadata or invent motivation
- Include ## My notes ONLY when the user hint or conversation clearly states a subjective opinion, stance, or framing
- Do not create empty sections or placeholder headings
- Do not include a ## Snapshot section
- Mention URLs only when they were central to the conversation; do not add a ## References section
- Honor the user's hint when present
- Do not invent facts not supported by the conversation or attached context
"""

    static func resolvedPagePrompt(from configuration: MarkExportConfiguration) -> String {
        let trimmed = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBase : configuration.systemPrompt
    }

    static func resolvedConversationPrompt(from configuration: MarkExportConfiguration) -> String {
        let trimmed = configuration.conversationSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? conversationBase : configuration.conversationSystemPrompt
    }

    static func isUsingDefaultPagePrompt(_ configuration: MarkExportConfiguration) -> Bool {
        normalized(configuration.systemPrompt) == normalized(defaultBase)
    }

    static func isUsingDefaultConversationPrompt(_ configuration: MarkExportConfiguration) -> Bool {
        normalized(configuration.conversationSystemPrompt) == normalized(conversationBase)
    }

    static func isUsingDefaultPrompt(_ configuration: MarkExportConfiguration) -> Bool {
        isUsingDefaultPagePrompt(configuration)
    }

    static func normalized(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
