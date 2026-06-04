import Foundation

enum MarkExportServiceError: LocalizedError {
    case invalidModelResponse
    case missingConfiguration(String)
    case missingPrimaryPage

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse:
            return "Cue could not parse the generated bookmark content."
        case let .missingConfiguration(message):
            return message
        case .missingPrimaryPage:
            return "Attach a web page before using /mark or //."
        }
    }
}

struct MarkExportService {
    private let conversationService: ConversationService
    private let noteWriter: ObsidianNoteWriter

    init(
        conversationService: ConversationService = ConversationService(),
        noteWriter: ObsidianNoteWriter = ObsidianNoteWriter()
    ) {
        self.conversationService = conversationService
        self.noteWriter = noteWriter
    }

    func generateAndSave(
        userHint: String,
        configuration: ConversationConfiguration,
        markConfiguration: MarkExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        onDebugLog: ((String) -> Void)? = nil
    ) async throws -> ObsidianNoteWriter.WriteResult {
        if let validationError = markConfiguration.validationError {
            throw MarkExportServiceError.missingConfiguration(validationError)
        }

        guard let exportFolderURL = markConfiguration.exportFolderURL else {
            throw MarkExportServiceError.missingConfiguration("Choose a mark export folder in Settings → Commands.")
        }

        guard let primaryPage = ConversationPageReferences.oldestPageReference(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
        ) else {
            throw MarkExportServiceError.missingPrimaryPage
        }

        let noteConfiguration = configuration.forNoteGeneration
        var requestMessages = contextualMessages + conversationMessages
        requestMessages.insert(
            ConversationPageReferences.primaryPageContextMessage(for: primaryPage),
            at: 0
        )

        let request = ConversationRequestDTO(
            systemPrompt: Self.generationSystemPrompt(
                configuration: markConfiguration,
                userHint: userHint,
                primaryPage: primaryPage,
                hasConversation: Self.hasSubstantiveConversation(conversationMessages)
            ),
            messages: requestMessages,
            messageAttachments: messageAttachments
        )

        CommandExportGenerationLogger.logMarkRequest(
            userHint: userHint,
            configuration: noteConfiguration,
            primaryPage: primaryPage,
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages,
            request: request,
            onDebugLog: onDebugLog
        )

        let response = try await conversationService.send(request: request, configuration: noteConfiguration)
        let generatedContent = try Self.parseGeneratedContent(from: response.message.text)
        let host = URL(string: primaryPage.url)?.host ?? ""

        let result = try noteWriter.write(
            ObsidianNoteWriter.WriteInput(
                title: generatedContent.title,
                body: generatedContent.body,
                sourceURL: primaryPage.url,
                references: [
                    ObsidianNoteWriter.Reference(title: primaryPage.title, url: primaryPage.url)
                ],
                createdAt: Date(),
                exportFolderURL: exportFolderURL,
                exportKind: .markPage(host: host)
            )
        )

        if let markdown = try? String(contentsOf: result.fileURL, encoding: .utf8) {
            CommandExportGenerationLogger.logWriteResult(
                label: "Mark",
                fileURL: result.fileURL,
                references: [ObsidianNoteWriter.Reference(title: primaryPage.title, url: primaryPage.url)],
                markdown: markdown,
                onDebugLog: onDebugLog
            )
        }

        return result
    }

    private static func hasSubstantiveConversation(_ messages: [ConversationMessageDTO]) -> Bool {
        messages.contains { message in
            guard message.role == .user || message.role == .assistant else {
                return false
            }

            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }

            if message.role == .user, ComposerCommandRegistry.parse(from: trimmed) != nil {
                return false
            }

            return true
        }
    }

    private static func generationSystemPrompt(
        configuration: MarkExportConfiguration,
        userHint: String,
        primaryPage: ConversationPageReferences.PageReference,
        hasConversation: Bool
    ) -> String {
        var prompt = MarkExportPrompts.resolvedBasePrompt(from: configuration)

        let hasUserHint = !userHint.isEmpty
        prompt += """


        Primary page (oldest in session): \(primaryPage.title) — \(primaryPage.url)
        Conversation present: \(hasConversation ? "yes" : "no")
        User hint present: \(hasUserHint ? "yes" : "no")
        """

        if hasUserHint {
            prompt += """

            The user described what they want to bookmark or emphasize:
            \(userHint)
            """
        }

        if !hasUserHint && !hasConversation {
            prompt += """

            There is no user hint and no substantive conversation. Omit ## Why I saved this and ## My angle unless the page content alone justifies a specific, non-generic reason. Prefer a lean note with ## What stood out only.
            """
        } else if !hasUserHint {
            prompt += """

            There is no user hint. Omit ## My angle unless the conversation clearly states the user's perspective. Only include ## Why I saved this if the conversation states a concrete reason to save this page.
            """
        } else if !hasConversation {
            prompt += """

            There is no conversation yet. Use the user hint for ## My angle when it expresses perspective; use ## Why I saved this only when the hint states a concrete reason. Do not invent motivation.
            """
        }

        return prompt
    }

    private struct GeneratedNoteContent: Decodable {
        let title: String
        let body: String
    }

    private static func parseGeneratedContent(from responseText: String) throws -> GeneratedNoteContent {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonPayload = extractJSONPayload(from: trimmed)

        guard let data = jsonPayload.data(using: .utf8) else {
            throw MarkExportServiceError.invalidModelResponse
        }

        do {
            return try JSONDecoder().decode(GeneratedNoteContent.self, from: data)
        } catch {
            throw MarkExportServiceError.invalidModelResponse
        }
    }

    private static func extractJSONPayload(from text: String) -> String {
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.hasPrefix("```") == true {
                lines.removeLast()
            }
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "json" {
                lines.removeFirst()
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            return String(text[start ... end])
        }

        return text
    }
}

private extension ConversationConfiguration {
    var forNoteGeneration: ConversationConfiguration {
        var copy = self
        copy.setWebSearchEnabled(false)
        return copy
    }
}
