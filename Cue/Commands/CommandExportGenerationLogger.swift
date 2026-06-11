import Foundation

enum CommandExportGenerationLogger {
    static func logMarkRequest(
        mode: MarkExportMode,
        userHint: String,
        configuration: ConversationConfiguration,
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        hasUsableContext: Bool,
        defaultSynthesisInstruction: MarkExportDefaultSynthesisInstruction.Result?,
        request: ConversationRequestDTO,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        let synthesisLine: String
        if let defaultSynthesisInstruction {
            synthesisLine = "Default synthesis: \(defaultSynthesisInstruction.scenario.rawValue)"
        } else {
            synthesisLine = "Default synthesis: (none)"
        }

        let modeLine: String = switch mode {
        case let .page(primaryPage):
            "Mode: page | Primary page: \(primaryPage.title) | \(primaryPage.url)"
        case .conversation:
            "Mode: conversation"
        }

        let systemPrompt = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsWhyISavedThisRule = systemPrompt.contains(MarkExportPrompts.whyISavedThisRuleMarker)

        let lines = [
            "=== Mark Export (/mark) Request ===",
            "Provider: \(configuration.providerDisplayName)",
            modeLine,
            "User hint: \(userHint.isEmpty ? "(none)" : userHint)",
            synthesisLine,
            "Usable context: \(hasUsableContext ? "yes" : "no")",
            "Browser pages in context stack: \(browserPageContexts.count)",
            "Contextual system messages: \(contextualMessages.count)",
            "Session messages: \(conversationMessages.count)",
            "Transcript messages: \(MarkExportConversationTranscript.messagesForGeneration(from: conversationMessages).count)",
            "Request messages: \(request.messages.count)",
            "System prompt chars: \(systemPrompt.count)",
            "Contains whyISavedThisRule: \(containsWhyISavedThisRule ? "yes" : "no")",
            "System prompt:\n\(systemPrompt)"
        ]

        log(lines.joined(separator: "\n"), onDebugLog: onDebugLog)
    }

    static func logMarkModelResponse(
        responseText: String,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? "(empty)" : trimmed

        log(
            [
                "=== Mark Export Model Response ===",
                "Response chars: \(trimmed.count)",
                body
            ].joined(separator: "\n"),
            onDebugLog: onDebugLog
        )
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

    private static func previewSuffix(_ text: String, limit: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else {
            return trimmed
        }

        return "…" + String(trimmed.suffix(limit))
    }

    private static func preview(_ message: ConversationMessageDTO) -> String {
        preview(message.text, limit: 120)
    }
}
