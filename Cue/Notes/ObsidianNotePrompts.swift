import Foundation

enum ObsidianNotePrompts {
    static let defaultBase = """
You turn a Cue conversation into a structured Obsidian markdown note.

Respond with ONLY valid JSON using this shape:
{"title":"Short descriptive title","body":"Markdown note body"}

Rules for the JSON values:
- title: concise, specific, under 80 characters
- body: markdown using ## Takeaways and ## Details when relevant
- Use bullet points for takeaways
- Do not invent facts not supported by the conversation or attached context
- Do not include a ## References section; Cue appends references automatically
- Do not wrap the JSON in markdown fences
"""

    static func resolvedBasePrompt(from configuration: ObsidianExportConfiguration) -> String {
        let trimmed = configuration.noteSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBase : configuration.noteSystemPrompt
    }

    static func isUsingDefaultPrompt(_ configuration: ObsidianExportConfiguration) -> Bool {
        normalized(configuration.noteSystemPrompt) == normalized(defaultBase)
    }

    static func normalized(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
