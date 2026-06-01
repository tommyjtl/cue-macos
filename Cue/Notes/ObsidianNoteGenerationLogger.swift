import Foundation

enum ObsidianNoteGenerationLogger {
    static func logRequest(
        userHint: String,
        configuration: ConversationConfiguration,
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        references: [ObsidianNoteService.NoteReference],
        request: ConversationRequestDTO,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        var lines = [
            "=== Obsidian Note Generation Request ===",
            "Provider: \(configuration.providerDisplayName)",
            "User hint: \(userHint.isEmpty ? "(none)" : userHint)",
            "Browser pages in context stack: \(browserPageContexts.count)"
        ]

        for page in browserPageContexts {
            lines.append("  • \(page.pageTitle) | \(page.url) | \(page.browserName)")
        }

        lines.append("Contextual system messages: \(contextualMessages.count)")
        for message in contextualMessages {
            lines.append("  • \(preview(message))")
        }

        lines.append("References collected: \(references.count)")
        if references.isEmpty {
            lines.append("  ⚠️ No references — References section will NOT be appended.")
            lines.append("  Tip: re-attach the web page before /note, or /note while the page is still in context.")
        } else {
            for reference in references {
                lines.append("  • \(reference.title) | \(reference.url)")
            }
        }

        lines.append("Conversation messages: \(conversationMessages.count)")
        for message in conversationMessages {
            var line = "  • [\(message.role.rawValue)] \(preview(message))"
            if !message.attachedContextLabels.isEmpty {
                line += " | labels: \(message.attachedContextLabels.joined(separator: ", "))"
            }
            if !message.attachedBrowserPages.isEmpty {
                line += " | pages: \(message.attachedBrowserPages.map(\.url).joined(separator: ", "))"
            }
            lines.append(line)
        }

        let attachmentCount = request.messageAttachments.values.reduce(0) { $0 + $1.count }
        lines.append("Image attachments: \(attachmentCount)")

        lines.append("System prompt:")
        lines.append(request.systemPrompt)

        lines.append("LLM messages (\(request.messages.count)):")
        for (index, message) in request.messages.enumerated() {
            lines.append("  \(index + 1). [\(message.role.rawValue)] \(preview(message))")
        }

        lines.append("=== End Obsidian Note Generation Request ===")

        emit(lines.joined(separator: "\n"), onDebugLog: onDebugLog)
    }

    static func logWriteResult(
        fileURL: URL,
        references: [ObsidianNoteWriter.Reference],
        markdown: String,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        let hasReferencesSection = markdown.localizedCaseInsensitiveContains("## References")
        let hasSourceFrontmatter = markdown.contains("source:")

        var lines = [
            "=== Obsidian Note Written ===",
            "Path: \(fileURL.path)",
            "References input: \(references.count)",
            "References section in file: \(hasReferencesSection ? "yes" : "no")",
            "Source frontmatter in file: \(hasSourceFrontmatter ? "yes" : "no")"
        ]

        if !references.isEmpty && !hasReferencesSection {
            lines.append("  ⚠️ References were expected but ## References is missing from the written file.")
        }

        lines.append("=== End Obsidian Note Written ===")

        emit(lines.joined(separator: "\n"), onDebugLog: onDebugLog)
    }

    private static func preview(_ message: ConversationMessageDTO, limit: Int = 240) -> String {
        let flattened = message.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard flattened.count > limit else {
            return flattened.isEmpty ? "(empty)" : flattened
        }

        return String(flattened.prefix(limit)) + "..."
    }

    private static func emit(_ message: String, onDebugLog: ((String) -> Void)?) {
        print("[ObsidianNote]\n\(message)")
        onDebugLog?(message)
    }
}
