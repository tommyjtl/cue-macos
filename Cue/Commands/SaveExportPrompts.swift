import Foundation

enum SaveExportPrompts {
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

    static func resolvedBasePrompt(from configuration: SaveExportConfiguration) -> String {
        let trimmed = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultBase : configuration.systemPrompt
    }

    static func isUsingDefaultPrompt(_ configuration: SaveExportConfiguration) -> Bool {
        normalized(configuration.systemPrompt) == normalized(defaultBase)
    }

    static func normalized(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ObsidianNotePrompts {
    static var defaultBase: String { SaveExportPrompts.defaultBase }

    static func resolvedBasePrompt(from configuration: SaveExportConfiguration) -> String {
        SaveExportPrompts.resolvedBasePrompt(from: configuration)
    }

    static func isUsingDefaultPrompt(_ configuration: SaveExportConfiguration) -> Bool {
        SaveExportPrompts.isUsingDefaultPrompt(configuration)
    }
}
