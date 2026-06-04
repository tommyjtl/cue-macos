import Foundation

enum MarkExportPrompts {
    static let defaultBase = """
You capture why a web page mattered to the user right now in Cue.

The PRIMARY page to bookmark is identified in the prompt (oldest page in the session). Center the note on that page.

Respond with ONLY valid JSON using this shape:
{"title":"Short descriptive title","body":"Markdown note body"}

Rules for the JSON values:
- title: concise, specific, under 80 characters; suitable for a filename
- body: use only sections that have real content (see below)
- Always include ## What stood out when the page context supports bullets or takeaways; put a prominent markdown link to the primary page here if other sections are omitted
- Include ## Why I saved this ONLY when the user hint or conversation gives a concrete reason beyond restating the page title—if you would only repeat metadata, omit this section entirely
- Include ## My angle ONLY when the user hint or conversation reveals their perspective, intent, or framing—if there is no hint and no substantive conversation, omit this section entirely
- Include ## From this conversation ONLY when there is a substantive back-and-forth (not just the /mark or // command); keep it short, not a session dump
- Do not create empty sections or placeholder headings
- Honor the user's hint about what they are bookmarking (blog, product, startup, docs, etc.) when present
- Do not invent facts not supported by the page context or conversation
- Do not include a ## References section listing other URLs
- Do not wrap the JSON in markdown fences
"""

    static func resolvedBasePrompt(from configuration: MarkExportConfiguration) -> String {
        let trimmed = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBase : configuration.systemPrompt
    }

    static func isUsingDefaultPrompt(_ configuration: MarkExportConfiguration) -> Bool {
        normalized(configuration.systemPrompt) == normalized(defaultBase)
    }

    static func normalized(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
