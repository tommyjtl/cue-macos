import Foundation

enum ObsidianNoteServiceError: LocalizedError {
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

struct ObsidianNoteService {
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
        obsidianConfiguration: ObsidianExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        onDebugLog: ((String) -> Void)? = nil
    ) async throws -> ObsidianNoteWriter.WriteResult {
        if let validationError = obsidianConfiguration.validationError {
            throw ObsidianNoteServiceError.missingConfiguration(validationError)
        }

        guard let exportFolderURL = obsidianConfiguration.exportFolderURL else {
            throw ObsidianNoteServiceError.missingConfiguration("Choose an Obsidian export folder in Settings.")
        }

        let noteConfiguration = configuration.forNoteGeneration
        let references = Self.collectReferences(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
        )
        let sourceURL = references.first?.url
        var requestMessages = contextualMessages + conversationMessages
        if let referenceMessage = Self.referenceContextMessage(for: references) {
            requestMessages.insert(referenceMessage, at: 0)
        }

        let request = ConversationRequestDTO(
            systemPrompt: Self.noteGenerationSystemPrompt(
                configuration: obsidianConfiguration,
                userHint: userHint,
                references: references
            ),
            messages: requestMessages,
            messageAttachments: messageAttachments
        )

        ObsidianNoteGenerationLogger.logRequest(
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
                exportFolderURL: exportFolderURL
            )
        )

        if let markdown = try? String(contentsOf: result.fileURL, encoding: .utf8) {
            ObsidianNoteGenerationLogger.logWriteResult(
                fileURL: result.fileURL,
                references: writerReferences,
                markdown: markdown,
                onDebugLog: onDebugLog
            )
        }

        return result
    }

    struct NoteReference: Equatable {
        let title: String
        let url: String
        let browserName: String
    }

    static func collectReferences(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO]
    ) -> [NoteReference] {
        var references: [NoteReference] = []
        var seenURLs = Set<String>()

        func appendReference(title: String, url: String, browserName: String) {
            guard seenURLs.insert(url).inserted else {
                return
            }

            references.append(
                NoteReference(
                    title: displayTitle(for: title, url: url),
                    url: url,
                    browserName: browserName
                )
            )
        }

        for page in browserPageContexts {
            appendReference(title: page.pageTitle, url: page.url, browserName: page.browserName)
        }

        for message in contextualMessages where message.role == .system {
            guard let reference = referenceFromContextMessage(message) else {
                continue
            }

            appendReference(title: reference.title, url: reference.url, browserName: reference.browserName)
        }

        for message in conversationMessages {
            for page in message.attachedBrowserPages {
                appendReference(title: page.pageTitle, url: page.url, browserName: page.browserName)
            }
        }

        return references
    }

    private static func referenceFromContextMessage(_ message: ConversationMessageDTO) -> NoteReference? {
        guard message.text.hasPrefix("Web page context from ") else {
            return nil
        }

        guard let urlStart = message.text.firstIndex(of: "("),
              let urlEnd = message.text[urlStart...].firstIndex(of: ")"),
              urlStart < urlEnd else {
            return nil
        }

        let url = String(message.text[message.text.index(after: urlStart)..<urlEnd])
        let browserName = message.text[
            message.text.index(message.text.startIndex, offsetBy: "Web page context from ".count)..<urlStart
        ]
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let pageTitle = message.text
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("Title: ") })
            .map { String($0.dropFirst("Title: ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""

        return NoteReference(
            title: displayTitle(for: pageTitle, url: url),
            url: url,
            browserName: browserName.isEmpty ? "Web" : browserName
        )
    }

    private static func displayTitle(for pageTitle: String, url: String) -> String {
        let trimmedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? url : trimmedTitle
    }

    private static func referenceContextMessage(for references: [NoteReference]) -> ConversationMessageDTO? {
        guard !references.isEmpty else {
            return nil
        }

        let lines = references.map { reference in
            "- \(reference.title): \(reference.url) (\(reference.browserName))"
        }

        return ConversationMessageDTO(
            role: .system,
            text: """
            Attached web page references for this note:
            \(lines.joined(separator: "\n"))

            Cue will append these as markdown links in a ## References section.
            """
        )
    }

    private static func noteGenerationSystemPrompt(
        configuration: ObsidianExportConfiguration,
        userHint: String,
        references: [NoteReference]
    ) -> String {
        var prompt = ObsidianNotePrompts.resolvedBasePrompt(from: configuration)

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
            throw ObsidianNoteServiceError.invalidModelResponse
        }

        do {
            return try JSONDecoder().decode(GeneratedNoteContent.self, from: data)
        } catch {
            throw ObsidianNoteServiceError.invalidModelResponse
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
