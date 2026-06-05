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
        let hasUserHint = !userHint.isEmpty
        let hasConversation = Self.hasSubstantiveConversation(conversationMessages)
        let hasRichPageText = ConversationPageReferences.primaryPageHasExtractedText(
            primaryPage: primaryPage,
            contextualMessages: contextualMessages
        )
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
                hasConversation: hasConversation,
                hasRichPageText: hasRichPageText
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
        var generatedContent = try MarkGeneratedContentParser.parse(
            response.message.text,
            fallbackTitle: primaryPage.title
        )

        if !hasUserHint && !hasConversation {
            let sanitizedBody = MarkExportBodySanitizer.sanitizeForPageOnlyBookmark(generatedContent.body)
            generatedContent = MarkGeneratedContentParser.Parsed(
                title: generatedContent.title,
                body: sanitizedBody
            )
        }

        let finalizedBody = MarkExportBodySanitizer.ensureMinimumContent(
            generatedContent.body,
            primaryPage: primaryPage,
            userHint: userHint
        )
        generatedContent = MarkGeneratedContentParser.Parsed(
            title: generatedContent.title,
            body: finalizedBody
        )

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
        hasConversation: Bool,
        hasRichPageText: Bool
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

        if !hasRichPageText {
            prompt += """

            Limited page text was captured (mostly title and URL). Still write a non-empty ## Highlights section with at least 2 short bullets inferred cautiously from the title, URL, and any visible context—never leave the body empty.
            """
        }

        if !hasUserHint && !hasConversation {
            prompt += """

            There is no user hint and no substantive conversation—only the /mark or // command and page context.
            Write ## Highlights only with substantive bullets or sentences. Do NOT include a lead paragraph, ## Why I saved this, or ## My notes. Do not infer why the user saved the page or state their opinion.
            """
        } else if !hasUserHint {
            prompt += """

            There is no user hint. Distill substantive conversation into a short lead paragraph before ## Highlights. Always include a non-empty ## Highlights section. Put bookmark motives and user questions in ## Why I saved this; use ## My notes only for clear subjective opinions.
            """
        } else if !hasConversation {
            prompt += """

            There is no conversation yet—no lead paragraph. Always include a non-empty ## Highlights section about the page. Honor the user's hint inside ## Highlights and/or ## Why I saved this as appropriate; use ## My notes only when the hint is clearly opinionated. Do not invent motivation or opinions.
            """
        } else {
            prompt += """

            Distill substantive conversation into a short lead paragraph before ## Highlights. Always include a non-empty ## Highlights section. Combine the hint and conversation for ## Why I saved this and ## My notes as appropriate.
            """
        }

        return prompt
    }
}

private extension ConversationConfiguration {
    var forNoteGeneration: ConversationConfiguration {
        var copy = self
        copy.setWebSearchEnabled(false)
        return copy
    }
}
