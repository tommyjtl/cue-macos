import Foundation

enum MarkExportPrompts {
    static let whyISavedThisRuleMarker = "questions the user actually asked"
    static let jsonOutputContractMarker = "\"body\""

    static let whyISavedThisRule = """
- Include ## Why I saved this when the user gives a concrete motive for keeping this beyond title, URL, or other surface context (e.g. deciding on a tool, following a launch, saving a draft to revisit) and/or asks questions worth preserving. Summarize questions the user actually asked—both explicit revisit asks and the ordinary questions they raised in the exchange—stated neutrally in their words. Omit if you would only repeat metadata or invent motivation or questions
"""

    static let jsonOutputContract = """
Output format (required):
Respond with a single JSON object only—no commentary before or after, no YAML frontmatter:
{"title":"Short plain-text title","body":"Markdown note body"}

- title: concise, specific, under 80 characters; suitable for a filename; not a markdown heading
- body: markdown only; must include substantive content (not just headings). Never return an empty body.
- Do not include a Tags line or ## References in the body
"""

    static let defaultBase = """
You turn attached web page context into a concise Obsidian bookmark.

The PRIMARY page to bookmark is identified in the prompt (oldest page in the session). Center the note on that page. Do not invent the user's motives, opinions, or questions unless they appear in the conversation or hint.

\(jsonOutputContract)

Body rules:
- Optional lead paragraph, then only sections that have real content (see below)
- When there was substantive back-and-forth (not just the /mark or // command), open the body with one short plain paragraph summarizing what the user explored—no heading, before ## Highlights; keep it brief, not a session dump
- Always include a non-empty ## Highlights section with at least a short paragraph about the page; include a prominent markdown link to the primary page
\(whyISavedThisRule)
- Include ## My notes ONLY when the user hint or conversation clearly states a subjective opinion, stance, or framing. Never infer this from the page alone
- Do not create empty sections or placeholder headings
- Honor the user's hint about what they are bookmarking (blog, product, startup, docs, etc.) when present
- Do not invent facts not supported by the page context or conversation
"""

    static let conversationBase = """
You turn a Cue conversation and any attached context (selected text, screenshots, prior messages) into a concise Obsidian note.

This is a conversation summary—not a web page bookmark. Center the note on what the user explored with Cue. Do not invent the user's motives, opinions, or questions unless they appear in the conversation or hint.

\(jsonOutputContract)

Body rules:
- Read the full user and assistant transcript in the messages below and synthesize it—do not ignore prior turns
- Open the body with one short plain paragraph summarizing what the user explored with Cue—no heading, before ## Highlights; keep it brief, not a session dump
- Always include a non-empty ## Highlights section with the main takeaways, answers, or decisions from the exchange
- Never copy the user's first message verbatim as the title
\(whyISavedThisRule)
- Include ## My notes ONLY when the user hint or conversation clearly states a subjective opinion, stance, or framing
- Do not create empty sections or placeholder headings
- Mention URLs only when they were central to the conversation
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

    static func ensuringGenerationInstructions(_ prompt: String) -> String {
        var trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.contains(whyISavedThisRuleMarker) {
            trimmed += "\n\n" + whyISavedThisRule.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !trimmed.contains(jsonOutputContractMarker) {
            trimmed += "\n\n" + jsonOutputContract.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
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
