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
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]]
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
            contextualMessages: contextualMessages
        )
        let sourceURL = references.first?.url
        var requestMessages = contextualMessages + conversationMessages
        if let referenceMessage = Self.referenceContextMessage(for: references) {
            requestMessages.insert(referenceMessage, at: 0)
        }

        let request = ConversationRequestDTO(
            systemPrompt: Self.noteGenerationSystemPrompt(userHint: userHint, references: references),
            messages: requestMessages,
            messageAttachments: messageAttachments
        )

        let response = try await conversationService.send(request: request, configuration: noteConfiguration)
        let generatedContent = try Self.parseGeneratedContent(from: response.message.text)

        return try noteWriter.write(
            ObsidianNoteWriter.WriteInput(
                title: generatedContent.title,
                body: generatedContent.body,
                sourceURL: sourceURL,
                references: references.map { ObsidianNoteWriter.Reference(title: $0.title, url: $0.url) },
                createdAt: Date(),
                exportFolderURL: exportFolderURL
            )
        )
    }

    struct NoteReference: Equatable {
        let title: String
        let url: String
        let browserName: String
    }

    private static func collectReferences(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO]
    ) -> [NoteReference] {
        var references: [NoteReference] = []
        var seenURLs = Set<String>()

        for page in browserPageContexts {
            guard seenURLs.insert(page.url).inserted else {
                continue
            }

            references.append(
                NoteReference(
                    title: displayTitle(for: page.pageTitle, url: page.url),
                    url: page.url,
                    browserName: page.browserName
                )
            )
        }

        for message in contextualMessages where message.role == .system {
            guard let reference = referenceFromContextMessage(message),
                  seenURLs.insert(reference.url).inserted else {
                continue
            }

            references.append(reference)
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

            Include every reference above in the note's ## References section as markdown links.
            """
        )
    }

    private static func noteGenerationSystemPrompt(userHint: String, references: [NoteReference]) -> String {
        var prompt = """
        You turn a Cue conversation into a structured Obsidian markdown note.

        Respond with ONLY valid JSON using this shape:
        {"title":"Short descriptive title","body":"Markdown note body"}

        Rules for the JSON values:
        - title: concise, specific, under 80 characters
        - body: markdown using ## Takeaways, ## Details, and ## References when relevant
        - Use bullet points for takeaways
        - Do not invent facts not supported by the conversation or attached context
        - Do not wrap the JSON in markdown fences
        """

        if !references.isEmpty {
            let referenceLines = references.map { "- [\($0.title)](\($0.url))" }.joined(separator: "\n")
            prompt += """


            The note must include a ## References section with these markdown links:
            \(referenceLines)
            """
        } else {
            prompt += """

            If web page sources appear in the conversation, include them in a ## References section as markdown links.
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
