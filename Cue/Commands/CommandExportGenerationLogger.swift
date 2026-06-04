import Foundation

enum CommandExportGenerationLogger {
    static func logMarkRequest(
        userHint: String,
        configuration: ConversationConfiguration,
        primaryPage: ConversationPageReferences.PageReference,
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        request: ConversationRequestDTO,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        let lines = [
            "=== Mark Export (/mark) Request ===",
            "Provider: \(configuration.providerDisplayName)",
            "User hint: \(userHint.isEmpty ? "(none)" : userHint)",
            "Primary page: \(primaryPage.title) | \(primaryPage.url)",
            "Browser pages in context stack: \(browserPageContexts.count)",
            "Contextual system messages: \(contextualMessages.count)",
            "Conversation messages: \(conversationMessages.count)",
            "System prompt preview: \(preview(request.systemPrompt))"
        ]

        log(lines.joined(separator: "\n"), onDebugLog: onDebugLog)
    }

    static func logWriteResult(
        label: String,
        fileURL: URL,
        references: [ObsidianNoteWriter.Reference],
        markdown: String,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        var lines = [
            "=== \(label) Export Write Result ===",
            "File: \(fileURL.path)",
            "References written: \(references.count)"
        ]

        for reference in references {
            lines.append("  • \(reference.title) | \(reference.url)")
        }

        lines.append("Markdown preview:\n\(preview(markdown))")
        log(lines.joined(separator: "\n"), onDebugLog: onDebugLog)
    }

    private static func log(_ message: String, onDebugLog: ((String) -> Void)?) {
        onDebugLog?(message)
    }

    private static func preview(_ text: String, limit: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else {
            return trimmed
        }

        return String(trimmed.prefix(limit)) + "…"
    }

    private static func preview(_ message: ConversationMessageDTO) -> String {
        preview(message.text, limit: 120)
    }
}
