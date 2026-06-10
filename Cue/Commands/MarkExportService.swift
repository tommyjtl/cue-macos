import Foundation

enum MarkExportServiceError: LocalizedError {
    case invalidModelResponse
    case missingConfiguration(String)
    case missingMarkableContent

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse:
            return "Cue could not parse the generated bookmark content."
        case let .missingConfiguration(message):
            return message
        case .missingMarkableContent:
            return "Send a message, attach context, or attach a web page before using /mark or //."
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
        mode: MarkExportMode,
        userHint: String,
        configuration: ConversationConfiguration,
        markConfiguration: MarkExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        usesImageOCR: Bool = false,
        automaticallyDetectLanguage: Bool = false,
        imageOCRCache: ImageOCRCache,
        onStatus: ((String) -> Void)? = nil,
        onDebugLog: ((String) -> Void)? = nil
    ) async throws -> ObsidianNoteWriter.WriteResult {
        if let validationError = markConfiguration.validationError {
            throw MarkExportServiceError.missingConfiguration(validationError)
        }

        guard let exportFolderURL = markConfiguration.exportFolderURL else {
            throw MarkExportServiceError.missingConfiguration("Choose a mark export folder in Settings → Commands.")
        }

        switch mode {
        case let .page(primaryPage):
            return try await generatePageMark(
                primaryPage: primaryPage,
                userHint: userHint,
                configuration: configuration,
                markConfiguration: markConfiguration,
                conversationMessages: conversationMessages,
                contextualMessages: contextualMessages,
                browserPageContexts: browserPageContexts,
                messageAttachments: messageAttachments,
                usesImageOCR: usesImageOCR,
                automaticallyDetectLanguage: automaticallyDetectLanguage,
                imageOCRCache: imageOCRCache,
                exportFolderURL: exportFolderURL,
                onStatus: onStatus,
                onDebugLog: onDebugLog
            )
        case .conversation:
            return try await generateConversationMark(
                userHint: userHint,
                configuration: configuration,
                markConfiguration: markConfiguration,
                conversationMessages: conversationMessages,
                contextualMessages: contextualMessages,
                messageAttachments: messageAttachments,
                usesImageOCR: usesImageOCR,
                automaticallyDetectLanguage: automaticallyDetectLanguage,
                imageOCRCache: imageOCRCache,
                exportFolderURL: exportFolderURL,
                onStatus: onStatus,
                onDebugLog: onDebugLog
            )
        }
    }

    private func generatePageMark(
        primaryPage: ConversationPageReferences.PageReference,
        userHint: String,
        configuration: ConversationConfiguration,
        markConfiguration: MarkExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        usesImageOCR: Bool,
        automaticallyDetectLanguage: Bool,
        imageOCRCache: ImageOCRCache,
        exportFolderURL: URL,
        onStatus: ((String) -> Void)?,
        onDebugLog: ((String) -> Void)?
    ) async throws -> ObsidianNoteWriter.WriteResult {
        let noteConfiguration = configuration.forNoteGeneration
        let hasUserHint = !userHint.isEmpty
        let hasConversation = Self.hasSubstantiveConversation(conversationMessages)
        let hasRichPageText = ConversationPageReferences.primaryPageHasExtractedText(
            primaryPage: primaryPage,
            contextualMessages: contextualMessages
        )
        let hasSelectedText = Self.hasSelectedText(in: contextualMessages)
        let hasUsableContext = hasRichPageText || hasSelectedText
        let defaultSynthesisInstruction = MarkExportDefaultSynthesisInstruction.resolve(
            userHint: userHint,
            hasConversation: hasConversation,
            primaryPage: primaryPage,
            contextualMessages: contextualMessages
        )
        var requestMessages = contextualMessages + conversationMessages
        requestMessages.insert(
            ConversationPageReferences.primaryPageContextMessage(for: primaryPage),
            at: 0
        )

        let systemPrompt = Self.pageGenerationSystemPrompt(
            configuration: markConfiguration,
            userHint: userHint,
            primaryPage: primaryPage,
            hasConversation: hasConversation,
            hasUsableContext: hasUsableContext,
            defaultSynthesisInstruction: defaultSynthesisInstruction
        )
        let request = try await ConversationRequestOCRPreprocessor.buildRequest(
            systemPrompt: systemPrompt,
            messages: requestMessages,
            messageAttachments: messageAttachments,
            usesImageOCR: usesImageOCR,
            automaticallyDetectLanguage: automaticallyDetectLanguage,
            imageOCRCache: imageOCRCache,
            onStatus: onStatus
        )

        CommandExportGenerationLogger.logMarkRequest(
            mode: .page(primaryPage: primaryPage),
            userHint: userHint,
            configuration: noteConfiguration,
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages,
            hasUsableContext: hasUsableContext,
            defaultSynthesisInstruction: defaultSynthesisInstruction,
            request: request,
            onDebugLog: onDebugLog
        )

        let response = try await conversationService.send(request: request, configuration: noteConfiguration)

        CommandExportGenerationLogger.logMarkModelResponse(
            responseText: response.message.text,
            onDebugLog: onDebugLog
        )
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

        var finalizedBody = MarkExportBodySanitizer.ensureMinimumContent(
            generatedContent.body,
            primaryPage: primaryPage,
            userHint: userHint
        )
        finalizedBody = Self.appendSnapshotIfEligible(
            to: finalizedBody,
            primaryPage: primaryPage,
            userHint: userHint,
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
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

        logWriteResult(
            result: result,
            references: [ObsidianNoteWriter.Reference(title: primaryPage.title, url: primaryPage.url)],
            onDebugLog: onDebugLog
        )

        return result
    }

    private func generateConversationMark(
        userHint: String,
        configuration: ConversationConfiguration,
        markConfiguration: MarkExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        usesImageOCR: Bool,
        automaticallyDetectLanguage: Bool,
        imageOCRCache: ImageOCRCache,
        exportFolderURL: URL,
        onStatus: ((String) -> Void)?,
        onDebugLog: ((String) -> Void)?
    ) async throws -> ObsidianNoteWriter.WriteResult {
        let noteConfiguration = configuration.forNoteGeneration
        let hasUserHint = !userHint.isEmpty
        let hasConversation = Self.hasSubstantiveConversation(conversationMessages)
        let hasSelectedText = Self.hasSelectedText(in: contextualMessages)
        let hasUsableContext = hasConversation || hasSelectedText || contextualMessages.contains { message in
            message.role == .system && message.text.contains("screenshot")
        }

        let transcriptMessages = MarkExportConversationTranscript.messagesForGeneration(
            from: conversationMessages
        )
        var requestMessages = contextualMessages
        requestMessages.append(MarkExportConversationTranscript.generationContextMessage())
        requestMessages.append(contentsOf: transcriptMessages)

        let fallbackTitle = MarkExportModeResolver.conversationFallbackTitle(
            conversationMessages: conversationMessages,
            userHint: userHint
        )
        let systemPrompt = Self.conversationGenerationSystemPrompt(
            configuration: markConfiguration,
            userHint: userHint,
            hasConversation: hasConversation,
            hasUsableContext: hasUsableContext,
            transcriptMessageCount: transcriptMessages.count
        )
        let request = try await ConversationRequestOCRPreprocessor.buildRequest(
            systemPrompt: systemPrompt,
            messages: requestMessages,
            messageAttachments: messageAttachments,
            usesImageOCR: usesImageOCR,
            automaticallyDetectLanguage: automaticallyDetectLanguage,
            imageOCRCache: imageOCRCache,
            onStatus: onStatus
        )

        CommandExportGenerationLogger.logMarkRequest(
            mode: .conversation,
            userHint: userHint,
            configuration: noteConfiguration,
            browserPageContexts: [],
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages,
            hasUsableContext: hasUsableContext,
            defaultSynthesisInstruction: nil,
            request: request,
            onDebugLog: onDebugLog
        )

        let response = try await conversationService.send(request: request, configuration: noteConfiguration)

        CommandExportGenerationLogger.logMarkModelResponse(
            responseText: response.message.text,
            onDebugLog: onDebugLog
        )
        var generatedContent = try MarkGeneratedContentParser.parse(
            response.message.text,
            fallbackTitle: fallbackTitle
        )
        generatedContent = MarkGeneratedContentParser.Parsed(
            title: MarkExportConversationTranscript.normalizedTitle(
                parsedTitle: generatedContent.title,
                conversationMessages: conversationMessages,
                userHint: userHint
            ),
            body: generatedContent.body
        )

        let finalizedBody = MarkExportBodySanitizer.ensureMinimumConversationContent(
            generatedContent.body,
            userHint: userHint,
            conversationMessages: conversationMessages
        )
        generatedContent = MarkGeneratedContentParser.Parsed(
            title: generatedContent.title,
            body: finalizedBody
        )

        let result = try noteWriter.write(
            ObsidianNoteWriter.WriteInput(
                title: generatedContent.title,
                body: generatedContent.body,
                sourceURL: nil,
                references: [],
                createdAt: Date(),
                exportFolderURL: exportFolderURL,
                exportKind: .markConversation
            )
        )

        logWriteResult(result: result, references: [], onDebugLog: onDebugLog)

        return result
    }

    static func hasSubstantiveConversation(_ messages: [ConversationMessageDTO]) -> Bool {
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

    private static func hasSelectedText(in contextualMessages: [ConversationMessageDTO]) -> Bool {
        contextualMessages.contains { message in
            message.role == .system && message.text.hasPrefix("Selected text from")
        }
    }

    private static func appendSnapshotIfEligible(
        to body: String,
        primaryPage: ConversationPageReferences.PageReference,
        userHint: String,
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO]
    ) -> String {
        guard let capture = ConversationPageReferences.primaryPageCapture(
            primaryPage: primaryPage,
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
        ) else {
            return body
        }

        guard MarkExportSnapshotEligibility.shouldIncludeSnapshot(
            primaryPage: primaryPage,
            extractedText: capture.extractedText,
            userHint: userHint
        ) else {
            return body
        }

        let snapshotSection = MarkExportSnapshotSection.build(
            extractedText: capture.extractedText,
            primaryPage: primaryPage,
            capturedAt: capture.capturedAt
        )

        return MarkExportSnapshotSection.append(to: body, snapshotSection: snapshotSection)
    }

    private static func pageGenerationSystemPrompt(
        configuration: MarkExportConfiguration,
        userHint: String,
        primaryPage: ConversationPageReferences.PageReference,
        hasConversation: Bool,
        hasUsableContext: Bool,
        defaultSynthesisInstruction: MarkExportDefaultSynthesisInstruction.Result?
    ) -> String {
        var prompt = MarkExportPrompts.resolvedPagePrompt(from: configuration)

        let hasUserHint = !userHint.isEmpty
        prompt += """


        Export mode: web page bookmark
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

        if !hasUsableContext {
            prompt += """

            Limited page text was captured (mostly title and URL). Still write a non-empty ## Highlights section with at least 2 short bullets inferred cautiously from the title, URL, and any visible context—never leave the body empty.
            """
        }

        prompt += pageScenarioInstructions(
            hasUserHint: hasUserHint,
            hasConversation: hasConversation,
            defaultSynthesisInstruction: defaultSynthesisInstruction
        )

        return prompt
    }

    private static func conversationGenerationSystemPrompt(
        configuration: MarkExportConfiguration,
        userHint: String,
        hasConversation: Bool,
        hasUsableContext: Bool,
        transcriptMessageCount: Int
    ) -> String {
        var prompt = MarkExportPrompts.resolvedConversationPrompt(from: configuration)

        let hasUserHint = !userHint.isEmpty
        prompt += """


        Export mode: conversation summary
        Conversation present: \(hasConversation ? "yes" : "no")
        Transcript messages included: \(transcriptMessageCount)
        User hint present: \(hasUserHint ? "yes" : "no")
        """

        if hasConversation {
            prompt += """

            A user and assistant transcript is included after the context messages.
            Summarize that exchange into the note. Include concrete takeaways from Cue's answer, not just the user's question.
            """
        }

        if hasUserHint {
            prompt += """

            The user described what they want to emphasize in this note:
            \(userHint)
            """
        }

        if !hasUsableContext {
            prompt += """

            Limited attached context was captured. Still write a non-empty ## Highlights section with at least 2 short bullets inferred cautiously from the conversation—never leave the body empty.
            """
        }

        if !hasUserHint {
            prompt += """

            Distill substantive conversation into the lead paragraph and ## Highlights. Put bookmark motives and user questions in ## Why I saved this when stated; use ## My notes only for clear subjective opinions.
            """
        } else {
            prompt += """

            Honor the user's hint inside ## Highlights and/or ## Why I saved this as appropriate. Combine the hint and conversation for the summary.
            """
        }

        return prompt
    }

    private static func pageScenarioInstructions(
        hasUserHint: Bool,
        hasConversation: Bool,
        defaultSynthesisInstruction: MarkExportDefaultSynthesisInstruction.Result?
    ) -> String {
        if !hasUserHint && !hasConversation {
            var instructions = """

            There is no user hint and no substantive conversation—only the mark command and page context.
            Write ## Highlights only with substantive bullets or sentences. Do NOT include a lead paragraph, ## Why I saved this, or ## My notes. Do not infer why the user saved the page or state their opinion.
            """

            if let defaultSynthesisInstruction {
                instructions += """


                Default synthesis task (user did not specify an angle; scenario: \(defaultSynthesisInstruction.scenario.rawValue)):
                \(defaultSynthesisInstruction.instruction)
                """
            }

            return instructions
        }

        if !hasUserHint {
            return """

            There is no user hint. Distill substantive conversation into a short lead paragraph before ## Highlights. Always include a non-empty ## Highlights section. Put bookmark motives and user questions in ## Why I saved this; use ## My notes only for clear subjective opinions.
            """
        }

        if !hasConversation {
            return """

            There is no conversation yet—no lead paragraph. Always include a non-empty ## Highlights section about the page. Honor the user's hint inside ## Highlights and/or ## Why I saved this as appropriate; use ## My notes only when the hint is clearly opinionated. Do not invent motivation or opinions.
            """
        }

        return """

        Distill substantive conversation into a short lead paragraph before ## Highlights. Always include a non-empty ## Highlights section. Combine the hint and conversation for ## Why I saved this and ## My notes as appropriate.
        """
    }

    private func logWriteResult(
        result: ObsidianNoteWriter.WriteResult,
        references: [ObsidianNoteWriter.Reference],
        onDebugLog: ((String) -> Void)?
    ) {
        if let markdown = try? String(contentsOf: result.fileURL, encoding: .utf8) {
            CommandExportGenerationLogger.logWriteResult(
                label: "Mark",
                fileURL: result.fileURL,
                references: references,
                markdown: markdown,
                onDebugLog: onDebugLog
            )
        }
    }
}

private extension ConversationConfiguration {
    var forNoteGeneration: ConversationConfiguration {
        var copy = self
        copy.setWebSearchEnabled(false)
        return copy
    }
}
