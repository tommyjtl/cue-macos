import Foundation

enum SaveExportServiceError: LocalizedError {
    case invalidModelResponse
    case missingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse:
            return "Cue could not parse the generated note content."
        case let .missingConfiguration(message):
            return message
        }
    }
}

struct SaveExportService {
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
        saveConfiguration: SaveExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        onDebugLog: ((String) -> Void)? = nil
    ) async throws -> ObsidianNoteWriter.WriteResult {
        let enabledMessage = "Enable \"Save conversations with /save\" in Settings → Commands."
        if let validationError = saveConfiguration.validationError(enabledMessage: enabledMessage) {
            throw SaveExportServiceError.missingConfiguration(validationError)
        }

        guard let exportFolderURL = saveConfiguration.exportFolderURL else {
            throw SaveExportServiceError.missingConfiguration("Choose a save export folder in Settings → Commands.")
        }

        let noteConfiguration = configuration.forNoteGeneration
        let references = ConversationPageReferences.collectReferences(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
        )
        let sourceURL = references.first?.url
        var requestMessages = contextualMessages + conversationMessages
        if let referenceMessage = ConversationPageReferences.referenceContextMessage(for: references) {
            requestMessages.insert(referenceMessage, at: 0)
        }

        let request = ConversationRequestDTO(
            systemPrompt: Self.generationSystemPrompt(
                configuration: saveConfiguration,
                userHint: userHint,
                references: references
            ),
            messages: requestMessages,
            messageAttachments: messageAttachments
        )

        CommandExportGenerationLogger.logSaveRequest(
            userHint: userHint,
            configuration: noteConfiguration,
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages,
            references: references,
            request: request,
            onDebugLog: onDebugLog
        )

        let response = try await conversationService.send(request: request, configuration: noteConfiguration)
        let generatedContent = try Self.parseGeneratedContent(from: response.message.text)
        let writerReferences = references.map { ObsidianNoteWriter.Reference(title: $0.title, url: $0.url) }

        let result = try noteWriter.write(
            ObsidianNoteWriter.WriteInput(
                title: generatedContent.title,
                body: generatedContent.body,
                sourceURL: sourceURL,
                references: writerReferences,
                createdAt: Date(),
                exportFolderURL: exportFolderURL,
                exportKind: .saveConversation
            )
        )

        if let markdown = try? String(contentsOf: result.fileURL, encoding: .utf8) {
            CommandExportGenerationLogger.logWriteResult(
                label: "Save",
                fileURL: result.fileURL,
                references: writerReferences,
                markdown: markdown,
                onDebugLog: onDebugLog
            )
        }

        return result
    }

    private static func generationSystemPrompt(
        configuration: SaveExportConfiguration,
        userHint: String,
        references: [ConversationPageReferences.PageReference]
    ) -> String {
        var prompt = SaveExportPrompts.resolvedBasePrompt(from: configuration)

        if !references.isEmpty {
            let referenceLines = references.map { "- \($0.title): \($0.url)" }.joined(separator: "\n")
            prompt += """


            These web page references will be appended to the note automatically:
            \(referenceLines)
            """
        } else {
            prompt += """

            If web page sources appear in the conversation, mention them in Details when relevant.
            """
        }

        if !userHint.isEmpty {
            prompt += """

            The user asked to emphasize this when writing the note:
            \(userHint)
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
            throw SaveExportServiceError.invalidModelResponse
        }

        do {
            return try JSONDecoder().decode(GeneratedNoteContent.self, from: data)
        } catch {
            throw SaveExportServiceError.invalidModelResponse
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
