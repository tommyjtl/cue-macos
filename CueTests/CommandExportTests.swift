import Foundation
import Testing
@testable import Cue

struct CommandExportTests {

    // MARK: - Save command

    @Test func saveCommandMatchesBareKeyword() {
        #expect(SaveCommand.parse(from: "/save")?.userHint == "")
        #expect(SaveCommand.parse(from: "  /save  ")?.userHint == "")
    }

    @Test func saveCommandMatchesWithHint() {
        #expect(SaveCommand.parse(from: "/save focus on localStorage pitfalls")?.userHint == "focus on localStorage pitfalls")
    }

    @Test func saveCommandRejectsLegacyNoteAliases() {
        #expect(SaveCommand.parse(from: "/note") == nil)
        #expect(SaveCommand.parse(from: "/notes") == nil)
        #expect(SaveCommand.parse(from: "/note focus on localStorage pitfalls") == nil)
    }

    @Test func saveCommandRejectsPartialKeywordMatches() {
        #expect(SaveCommand.parse(from: "/notebook") == nil)
        #expect(SaveCommand.parse(from: "please /save later") == nil)
    }

    @Test func saveCommandRequiresConversationOrContextBeforeExport() {
        #expect(
            SaveCommand.hasExportableContent(
                sessionMessages: [],
                screenshotCount: 0,
                selectedTextContextCount: 0,
                browserPageContextCount: 0
            ) == false
        )
        #expect(
            SaveCommand.hasExportableContent(
                sessionMessages: [ConversationMessageDTO(role: .user, text: "Summarize this.")],
                screenshotCount: 0,
                selectedTextContextCount: 0,
                browserPageContextCount: 0
            )
        )
    }

    @Test func registryPrefersMarkOverSavePrefix() {
        #expect(MarkCommand.parse(from: "// startup idea")?.userHint == "startup idea")
        #expect(ComposerCommandRegistry.parse(from: "// blog") != nil)
        if case let .mark(parsed) = ComposerCommandRegistry.parse(from: "// blog") {
            #expect(parsed.userHint == "blog")
        } else {
            Issue.record("Expected mark command")
        }
    }

    @Test func composerHighlightsLeadingKeywordRange() {
        #expect(SaveCommand.leadingKeywordRange(in: "/save focus")?.lowerBound == "/save focus".startIndex)
        #expect(MarkCommand.leadingKeywordRange(in: "// blog")?.lowerBound == "// blog".startIndex)
        #expect(ComposerCommandRegistry.leadingKeywordRange(in: "/notebook") == nil)
    }

    // MARK: - Mark command

    @Test func composerNormalizesLeadingDoubleSlashToMark() {
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("//") == "/mark ")
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("// startup") == "/mark startup")
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("//startup") == "/mark startup")
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("/mark") == "/mark ")
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("/mark startup") == "/mark startup")
        #expect(ComposerCommandTextNormalizer.normalizeComposerDraft("say // later") == "say // later")
    }

    @Test func composerDoesNotReexpandMarkWhenDeletingTrailingSpace() {
        let normalization = ComposerCommandTextNormalizer.normalizingComposerDraftIfNeeded(
            "/mark",
            previousText: "/mark "
        )

        #expect(normalization.didReplace == false)
        #expect(normalization.text == "/mark")
    }

    @Test func composerStillExpandsMarkWhenTypingForward() {
        let normalization = ComposerCommandTextNormalizer.normalizingComposerDraftIfNeeded(
            "/mark",
            previousText: "/mar"
        )

        #expect(normalization.didReplace == true)
        #expect(normalization.text == "/mark ")
    }

    @Test func composerAdjustedSelectedRangeAfterBareMarkExpansion() {
        let bareDoubleSlashRange = ComposerCommandTextNormalizer.adjustedSelectedRange(
            originalRange: NSRange(location: 2, length: 0),
            originalText: "//",
            normalizedText: "/mark "
        )
        #expect(bareDoubleSlashRange.location == 6)

        let bareMarkRange = ComposerCommandTextNormalizer.adjustedSelectedRange(
            originalRange: NSRange(location: 5, length: 0),
            originalText: "/mark",
            normalizedText: "/mark "
        )
        #expect(bareMarkRange.location == 6)
    }

    @Test func markCommandMatchesBareKeyword() {
        #expect(MarkCommand.parse(from: "/mark")?.userHint == "")
        #expect(MarkCommand.parse(from: "//")?.userHint == "")
    }

    @Test func markCommandMatchesWithHint() {
        #expect(MarkCommand.parse(from: "/mark startup")?.userHint == "startup")
        #expect(MarkCommand.parse(from: "// product launch")?.userHint == "product launch")
    }

    @Test func markCommandRejectsPartialMatches() {
        #expect(MarkCommand.parse(from: "https://example.com") == nil)
        #expect(MarkCommand.parse(from: "say // later") == nil)
    }

    @Test func markGeneratedContentParserRequiresJSONResponse() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            {"title":"Fallow — codebase intelligence for TypeScript","body":"## Highlights\\n\\n- Useful for large JS repos"}
            """
        )

        #expect(parsed.title == "Fallow — codebase intelligence for TypeScript")
        #expect(parsed.body.hasPrefix("## Highlights"))
    }

    @Test func markGeneratedContentParserRejectsMarkdownOnlyResponse() {
        #expect(throws: MarkExportServiceError.invalidModelResponse) {
            try MarkGeneratedContentParser.parse(
                """
                Fallow — codebase intelligence for TypeScript
                ## Highlights
                - Useful for large JS repos
                """
            )
        }
    }

    @Test func markWriterUsesCueTagInFrontmatter() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-mark-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let writer = ObsidianNoteWriter()
        let createdAt = ISO8601DateFormatter().date(from: "2026-06-05T02:24:18Z") ?? Date()
        let result = try writer.write(
            ObsidianNoteWriter.WriteInput(
                title: "Security Field Report",
                body: "## Highlights\n\n- Useful methodology",
                sourceURL: "https://example.com/report",
                references: [],
                createdAt: createdAt,
                exportFolderURL: rootDirectory,
                exportKind: .markPage(host: "example.com")
            )
        )

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(markdown.contains("tags: [cue]"))
    }

    @Test func markGeneratedContentParserAcceptsJSONInMarkdownFences() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            ```json
            {"title":"Startup launch notes","body":"## Why I saved this\\n\\n- Comparing against Linear."}
            ```
            """,
            fallbackTitle: "Fallback"
        )

        #expect(parsed.title == "Startup launch notes")
        #expect(parsed.body.contains("## Why I saved this"))
    }

    @Test func markGeneratedContentParserRejectsEmptyBody() {
        #expect(throws: MarkExportServiceError.invalidModelResponse) {
            try MarkGeneratedContentParser.parse(
                "{\"title\":\"MotherDuck\",\"body\":\"## Highlights\"}"
            )
        }
    }

    @Test func markGeneratedContentParserUsesFallbackTitleWhenJSONTitleEmpty() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            "{\"title\":\"\",\"body\":\"## Highlights\\n\\n- One takeaway\"}",
            fallbackTitle: "Page title from browser"
        )

        #expect(parsed.title == "Page title from browser")
    }

    @Test func markWriterSanitizesBraceCharactersInFileName() {
        #expect(
            ObsidianNoteWriter.fileName(
                from: "{title-Bad-,-body-##",
                exportKind: .markPage(host: "example.com")
            ) == "title-Bad-,-body-##.md"
        )
    }

    @Test func markBodySanitizerDetectsSubstantiveContent() {
        #expect(MarkExportBodySanitizer.hasSubstantiveContent("## Highlights\n\n- Useful methodology"))
        #expect(!MarkExportBodySanitizer.hasSubstantiveContent("## Highlights"))
        #expect(!MarkExportBodySanitizer.hasSubstantiveContent(""))
    }

    @Test func primaryPageHasExtractedTextDetectsThinContext() {
        let reference = ConversationPageReferences.PageReference(
            title: "Thin Page",
            url: "https://example.com/thin",
            browserName: "Safari"
        )

        let thinContext = [
            ConversationMessageDTO(
                role: .system,
                text: "Web page context from Safari (https://example.com/thin):\nTitle: Thin Page"
            )
        ]
        #expect(
            ConversationPageReferences.primaryPageHasExtractedText(
                primaryPage: reference,
                contextualMessages: thinContext
            ) == false
        )

        let richContext = [
            ConversationMessageDTO(
                role: .system,
                text: """
                Web page context from Safari (https://example.com/thin):
                Title: Thin Page

                This article explains how bindery workflows integrate with press operations.
                """
            )
        ]
        #expect(
            ConversationPageReferences.primaryPageHasExtractedText(
                primaryPage: reference,
                contextualMessages: richContext
            )
        )
    }

    @Test func markGeneratedContentParserAcceptsJSONWrappedInFences() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            ```json
            {"title":"Page bookmark title","body":"## Highlights\\n\\n- Item one"}
            ```
            """
        )

        #expect(parsed.title == "Page bookmark title")
        #expect(parsed.body.contains("Item one"))
    }

    @Test func oldestPageReferenceUsesFirstUserMessageAttachment() {
        let reference = ConversationPageReferences.oldestPageReference(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: [
                ConversationMessageDTO(
                    role: .user,
                    text: "hello",
                    attachedBrowserPages: [
                        AttachedBrowserPageReference(
                            url: "https://first.example/page",
                            pageTitle: "First Page",
                            browserName: "Chrome"
                        )
                    ]
                ),
                ConversationMessageDTO(
                    role: .user,
                    text: "follow up",
                    attachedBrowserPages: [
                        AttachedBrowserPageReference(
                            url: "https://second.example/page",
                            pageTitle: "Second Page",
                            browserName: "Chrome"
                        )
                    ]
                )
            ]
        )

        #expect(reference?.url == "https://first.example/page")
    }

    @Test func oldestPageReferenceUsesOldestAttachmentWithinUserMessage() {
        let reference = ConversationPageReferences.oldestPageReference(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: [
                ConversationMessageDTO(
                    role: .user,
                    text: "/mark",
                    attachedBrowserPages: [
                        AttachedBrowserPageReference(
                            url: "https://newest.example/page",
                            pageTitle: "Newest Page",
                            browserName: "Chrome"
                        ),
                        AttachedBrowserPageReference(
                            url: "https://oldest.example/page",
                            pageTitle: "Oldest Page",
                            browserName: "Chrome"
                        )
                    ]
                )
            ]
        )

        #expect(reference?.url == "https://oldest.example/page")
    }

    @Test func oldestPageReferenceUsesOldestPageOnContextStack() {
        let oldest = BrowserPageContext(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            url: "https://oldest.example/page",
            pageTitle: "Oldest Page",
            extractedText: "",
            browserName: "Safari"
        )
        let newest = BrowserPageContext(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 2),
            url: "https://newest.example/page",
            pageTitle: "Newest Page",
            extractedText: "",
            browserName: "Safari"
        )

        let reference = ConversationPageReferences.oldestPageReference(
            browserPageContexts: [newest, oldest],
            contextualMessages: [],
            conversationMessages: []
        )

        #expect(reference?.url == "https://oldest.example/page")
    }

    @Test func markCommandDetectsPageOnStackWhenNoMessages() {
        let page = BrowserPageContext(
            id: UUID(),
            createdAt: Date(),
            url: "https://example.com/article",
            pageTitle: "Article",
            extractedText: "Body",
            browserName: "Safari"
        )
        #expect(
            MarkCommand.hasMarkableContent(
                browserPageContexts: [page],
                contextualMessages: [],
                conversationMessages: [],
                screenshotCount: 0,
                selectedTextContextCount: 0
            )
        )
    }

    @Test func markModeUsesPageBookmarkWhenSessionBeganWithWebPage() {
        let page = BrowserPageContext(
            id: UUID(),
            createdAt: Date(),
            url: "https://example.com/article",
            pageTitle: "Article",
            extractedText: "Body",
            browserName: "Chrome"
        )

        let mode = MarkExportModeResolver.resolve(
            browserPageContexts: [page],
            contextualMessages: [],
            conversationMessages: [],
            screenshotCount: 0,
            selectedTextContextCount: 0
        )

        #expect(mode == .page(primaryPage: ConversationPageReferences.PageReference(
            title: "Article",
            url: "https://example.com/article",
            browserName: "Chrome"
        )))
    }

    @Test func markModeUsesConversationSummaryWhenFirstMessageHadNoWebPage() {
        let page = BrowserPageContext(
            id: UUID(),
            createdAt: Date(),
            url: "https://example.com/added-later",
            pageTitle: "Added later",
            extractedText: "Body",
            browserName: "Chrome"
        )
        let messages = [
            ConversationMessageDTO(role: .user, text: "What does this selection mean?"),
            ConversationMessageDTO(role: .assistant, text: "It highlights the key constraint.")
        ]

        let mode = MarkExportModeResolver.resolve(
            browserPageContexts: [page],
            contextualMessages: [],
            conversationMessages: messages,
            screenshotCount: 0,
            selectedTextContextCount: 0
        )

        #expect(mode == .conversation)
    }

    @Test func markModeUsesConversationSummaryForChatWithSelectionOnly() {
        let mode = MarkExportModeResolver.resolve(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: [],
            screenshotCount: 0,
            selectedTextContextCount: 1
        )

        #expect(mode == .conversation)
    }

    @Test func markModeRejectsEmptyMarkWithNoContent() {
        let mode = MarkExportModeResolver.resolve(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: [],
            screenshotCount: 0,
            selectedTextContextCount: 0
        )

        #expect(mode == nil)
    }

    @Test func conversationContextBuildOmitsHistoricalWebPagesWhenDisabled() {
        let messages = [
            ConversationMessageDTO(
                role: .user,
                text: "What does this selection mean?",
                attachedBrowserPages: [
                    AttachedBrowserPageReference(
                        url: "https://example.com/added-later",
                        pageTitle: "Added later",
                        browserName: "Chrome",
                        extractedText: "Leaked page body"
                    )
                ]
            )
        ]

        let contextualMessages = ConversationContextMessages.build(
            sessionMessages: messages,
            selectedTextContexts: [],
            browserPageContexts: [
                BrowserPageContext(
                    id: UUID(),
                    createdAt: Date(),
                    url: "https://example.com/stack-page",
                    pageTitle: "Stack page",
                    extractedText: "Stack body",
                    browserName: "Chrome"
                )
            ],
            includeWebPageContext: false
        )

        #expect(contextualMessages.isEmpty)
    }

    @Test func markConfigurationDecodesLegacyPayloadWithoutConversationPrompt() throws {
        let data = try JSONEncoder().encode(
            MarkExportConfiguration(
                isEnabled: true,
                exportFolderPath: "/tmp/mark",
                systemPrompt: MarkExportPrompts.defaultBase
            )
        )

        let decoded = try JSONDecoder().decode(MarkExportConfiguration.self, from: data)
        #expect(decoded.conversationSystemPrompt == MarkExportPrompts.conversationBase)
    }

    @Test func conversationTranscriptMessagesExcludeMarkCommand() {
        let messages = [
            ConversationMessageDTO(role: .user, text: "What is a sidecar?"),
            ConversationMessageDTO(role: .assistant, text: "A sidecar is a helper process alongside the main service."),
            ConversationMessageDTO(role: .user, text: "/mark")
        ]

        let transcript = MarkExportConversationTranscript.messagesForGeneration(from: messages)

        #expect(transcript.count == 2)
        #expect(transcript[0].text == "What is a sidecar?")
        #expect(transcript[1].text.contains("helper process"))
    }

    @Test func conversationTranscriptMessagesExcludeSavedNoteConfirmations() {
        let messages = [
            ConversationMessageDTO(role: .user, text: "what is mother duck?"),
            ConversationMessageDTO(role: .assistant, text: "MotherDuck is a cloud warehouse."),
            ConversationMessageDTO(
                role: .assistant,
                text: ObsidianSavedNoteMessage.confirmationText(filePath: "/tmp/bookmarks/note.md")
            ),
            ConversationMessageDTO(role: .user, text: "/mark")
        ]

        let transcript = MarkExportConversationTranscript.messagesForGeneration(from: messages)

        #expect(transcript.count == 2)
        #expect(!transcript.contains { $0.text.contains("Saved to Obsidian") })
    }

    @Test func pageGenerationRequestUsesFilteredTranscript() {
        let messages = [
            ConversationMessageDTO(role: .user, text: "what is duck db?"),
            ConversationMessageDTO(role: .assistant, text: "DuckDB is an in-process database."),
            ConversationMessageDTO(role: .user, text: "/mark"),
            ConversationMessageDTO(
                role: .assistant,
                text: ObsidianSavedNoteMessage.confirmationText(filePath: "/tmp/old.md")
            ),
            ConversationMessageDTO(role: .user, text: "/mark")
        ]

        let requestMessages = MarkExportConversationTranscript.generationRequestMessages(
            contextualMessages: [],
            conversationMessages: messages,
            userHint: "",
            includeTranscriptFraming: true
        )

        #expect(requestMessages.count == 3)
        #expect(requestMessages[0].text.contains("Cue conversation to summarize"))
        #expect(requestMessages[1].text == "what is duck db?")
        #expect(requestMessages[2].text.contains("in-process database"))
        #expect(!requestMessages.contains { $0.text.hasPrefix("/mark") })
        #expect(!requestMessages.contains { $0.text.contains("Saved to Obsidian") })
    }

    @Test func conversationGenerationRequestIncludesMarkTurnScreenshotMessage() {
        let messageID = UUID()
        let messages = [
            ConversationMessageDTO(role: .user, text: "What is a sidecar?"),
            ConversationMessageDTO(role: .assistant, text: "A sidecar is a helper process."),
            ConversationMessageDTO(
                id: messageID,
                role: .user,
                text: "/mark architecture diagram",
                imageAttachments: [
                    ConversationImageAttachmentReference(
                        id: UUID(),
                        mimeType: "image/png",
                        relativePath: "screenshots/test.png"
                    )
                ]
            )
        ]

        let requestMessages = MarkExportConversationTranscript.generationRequestMessages(
            contextualMessages: [],
            conversationMessages: messages,
            userHint: "architecture diagram"
        )

        #expect(!requestMessages.contains { $0.text == "/mark architecture diagram" })
        #expect(requestMessages.contains { $0.role == .system && $0.text.contains("Cue conversation to summarize") })

        let markTurnMessage = requestMessages.last
        #expect(markTurnMessage?.id == messageID)
        #expect(markTurnMessage?.text == "architecture diagram")
        #expect(markTurnMessage?.imageAttachments.count == 1)
    }

    @Test func conversationMarkTurnAttachmentMessageRequiresScreenshots() {
        let messages = [
            ConversationMessageDTO(role: .user, text: "What is a sidecar?"),
            ConversationMessageDTO(role: .assistant, text: "A sidecar is a helper process."),
            ConversationMessageDTO(role: .user, text: "/mark")
        ]

        #expect(
            MarkExportConversationTranscript.markTurnAttachmentMessage(
                from: messages,
                userHint: ""
            ) == nil
        )
    }


    @Test func resolvedConversationPromptUsesCustomConfiguration() {
        let customPrompt = "Custom conversation mark prompt."
        let configuration = MarkExportConfiguration(
            isEnabled: true,
            exportFolderPath: "/tmp/mark",
            systemPrompt: MarkExportPrompts.defaultBase,
            conversationSystemPrompt: customPrompt
        )

        #expect(MarkExportPrompts.resolvedConversationPrompt(from: configuration) == customPrompt)
    }

    @Test func markModeUsesPageWhenFirstUserMessageAttachedWebPage() {
        let messages = [
            ConversationMessageDTO(
                role: .user,
                text: "Summarize this article",
                attachedBrowserPages: [
                    AttachedBrowserPageReference(
                        url: "https://example.com/post",
                        pageTitle: "Post",
                        browserName: "Chrome",
                        extractedText: "Article body"
                    )
                ]
            )
        ]

        let mode = MarkExportModeResolver.resolve(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: messages,
            screenshotCount: 0,
            selectedTextContextCount: 0
        )

        #expect(mode == .page(primaryPage: ConversationPageReferences.PageReference(
            title: "Post",
            url: "https://example.com/post",
            browserName: "Chrome"
        )))
    }

    // MARK: - Writer

    @Test func noteWriterCreatesDateFolderAndMarkdownFile() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-save-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let components = DateComponents(
            calendar: Calendar.current,
            timeZone: .current,
            year: 2026,
            month: 5,
            day: 30,
            hour: 14,
            minute: 32
        )
        let createdAt = Calendar.current.date(from: components)!
        let writer = ObsidianNoteWriter()
        let result = try writer.write(
            ObsidianNoteWriter.WriteInput(
                title: "LocalStorage Pitfalls",
                body: "## Takeaways\n\n- Avoid storing objects directly",
                sourceURL: "https://example.com/article",
                references: [
                    ObsidianNoteWriter.Reference(title: "Example Article", url: "https://example.com/article")
                ],
                createdAt: createdAt,
                exportFolderURL: rootDirectory,
                exportKind: .saveConversation
            )
        )

        #expect(result.title == "LocalStorage Pitfalls")
        #expect(result.fileURL.path.contains("2026-05-30"))
        #expect(result.fileURL.lastPathComponent == "LocalStorage Pitfalls.md")

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(markdown.contains("tags: [cue, save]"))
        #expect(markdown.contains("## References"))
    }

    @Test func markWriterUsesTitleOnlyFileName() {
        let fileName = ObsidianNoteWriter.fileName(
            from: "Supertonic ONNX",
            exportKind: .markPage(host: "github.com")
        )
        #expect(fileName == "Supertonic ONNX.md")
    }

    @Test func noteWriterSanitizesFileNames() {
        #expect(ObsidianNoteWriter.fileName(from: "Hello, World!") == "Hello, World!.md")
        #expect(ObsidianNoteWriter.fileName(from: "Bad/Name:Here") == "Bad-Name-Here.md")
    }

    @Test func collectReferencesUsesPersistedConversationPages() {
        let references = ConversationPageReferences.collectReferences(
            browserPageContexts: [],
            contextualMessages: [],
            conversationMessages: [
                ConversationMessageDTO(
                    role: .user,
                    text: "what is this video about?",
                    attachedBrowserPages: [
                        AttachedBrowserPageReference(
                            url: "https://www.youtube.com/watch?v=example",
                            pageTitle: "Chinese comedy roast compilation",
                            browserName: "Chrome"
                        )
                    ]
                ),
                ConversationMessageDTO(role: .user, text: "/save")
            ]
        )

        #expect(references.count == 1)
        #expect(references[0].url == "https://www.youtube.com/watch?v=example")
    }

    @Test func savedNoteMessageParsesFilePath() {
        let path = "/Users/example/Obsidian/Vault/2026-06-03/Note title.md"
        let message = ObsidianSavedNoteMessage.confirmationText(filePath: path)

        #expect(ObsidianSavedNoteMessage.savedNoteFileURL(from: message)?.path == path)
    }

    @Test func saveConfigurationOnlyRequiresEnabledToggle() {
        let disabledSave = SaveExportConfiguration(isEnabled: false)
        #expect(
            disabledSave.validationError(enabledMessage: "Enable save.") == "Enable save."
        )

        let enabledSave = SaveExportConfiguration(isEnabled: true)
        #expect(enabledSave.validationError(enabledMessage: "Enable save.") == nil)
    }

    @Test func markConfigurationRequiresExportFolder() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-mark-config-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let disabledMark = MarkExportConfiguration(isEnabled: false, exportFolderPath: rootDirectory.path)
        #expect(disabledMark.validationError != nil)

        let enabledMark = MarkExportConfiguration(isEnabled: true, exportFolderPath: rootDirectory.path)
        #expect(enabledMark.validationError == nil)
    }

    @Test func markDefaultSynthesisInstructionDetectsYouTubeURLs() {
        #expect(MarkExportDefaultSynthesisInstruction.isYouTubeURL("https://www.youtube.com/watch?v=abc123"))
        #expect(MarkExportDefaultSynthesisInstruction.isYouTubeURL("https://youtu.be/abc123"))
        #expect(MarkExportDefaultSynthesisInstruction.isYouTubeURL("https://m.youtube.com/watch?v=abc123"))
        #expect(!MarkExportDefaultSynthesisInstruction.isYouTubeURL("https://example.com/article"))
    }

    @Test func markDefaultSynthesisInstructionForYouTubeWithSelectedTextWithoutUserHint() {
        let primaryPage = ConversationPageReferences.PageReference(
            title: "RAG vs Agentic AI",
            url: "https://www.youtube.com/watch?v=example",
            browserName: "Chrome"
        )
        let contextualMessages = [
            ConversationMessageDTO(
                role: .system,
                text: """
                Selected text from Chrome:

                Gemini summary covering how LLMs connect data for smarter AI.
                """
            )
        ]

        let result = MarkExportDefaultSynthesisInstruction.resolve(
            userHint: "",
            hasConversation: false,
            primaryPage: primaryPage,
            contextualMessages: contextualMessages
        )

        #expect(result?.scenario == .youtubeVideo)
        #expect(result?.presetGeneratingContext.scenarioLabel == "YouTube video")
        #expect(result?.presetGeneratingContext.hint.contains("at least 3 bullets") == true)
    }

    @Test func markDefaultSynthesisInstructionSkippedWhenUserHintPresent() {
        let primaryPage = ConversationPageReferences.PageReference(
            title: "RAG vs Agentic AI",
            url: "https://www.youtube.com/watch?v=example",
            browserName: "Chrome"
        )

        let result = MarkExportDefaultSynthesisInstruction.resolve(
            userHint: "focus on how agents connect data",
            hasConversation: false,
            primaryPage: primaryPage,
            contextualMessages: []
        )

        #expect(result == nil)
    }

    @Test func markDefaultSynthesisInstructionSkippedForNonYouTubePage() {
        let primaryPage = ConversationPageReferences.PageReference(
            title: "Example Article",
            url: "https://example.com/article",
            browserName: "Chrome"
        )

        let result = MarkExportDefaultSynthesisInstruction.resolve(
            userHint: "",
            hasConversation: false,
            primaryPage: primaryPage,
            contextualMessages: []
        )

        #expect(result == nil)
    }

    // MARK: - Snapshot

    @Test func snapshotEligibilityAcceptsLongArticlePaths() {
        let page = ConversationPageReferences.PageReference(
            title: "Example Article",
            url: "https://example.com/blog/example-article",
            browserName: "Chrome"
        )
        let extractedText = String(repeating: "Paragraph about the article. ", count: 30)

        #expect(
            MarkExportSnapshotEligibility.shouldIncludeSnapshot(
                primaryPage: page,
                extractedText: extractedText,
                userHint: ""
            )
        )
    }

    @Test func snapshotEligibilityRejectsHomepageAndYouTube() {
        let homepage = ConversationPageReferences.PageReference(
            title: "Acme",
            url: "https://acme.com/",
            browserName: "Chrome"
        )
        let youtube = ConversationPageReferences.PageReference(
            title: "Video",
            url: "https://www.youtube.com/watch?v=abc123",
            browserName: "Chrome"
        )
        let longText = String(repeating: "Body text. ", count: 80)

        #expect(
            !MarkExportSnapshotEligibility.shouldIncludeSnapshot(
                primaryPage: homepage,
                extractedText: longText,
                userHint: ""
            )
        )
        #expect(
            !MarkExportSnapshotEligibility.shouldIncludeSnapshot(
                primaryPage: youtube,
                extractedText: longText,
                userHint: ""
            )
        )
    }

    @Test func snapshotEligibilityHonorsExplicitArchiveHint() {
        let homepage = ConversationPageReferences.PageReference(
            title: "Acme",
            url: "https://acme.com/",
            browserName: "Chrome"
        )

        #expect(
            MarkExportSnapshotEligibility.shouldIncludeSnapshot(
                primaryPage: homepage,
                extractedText: "Short page copy.",
                userHint: "archive this page verbatim"
            )
        )
    }

    @Test func snapshotSectionAppendsCapturedArticleText() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let page = ConversationPageReferences.PageReference(
            title: "Example Article",
            url: "https://example.com/blog/example-article",
            browserName: "Chrome"
        )
        let snapshot = MarkExportSnapshotSection.build(
            extractedText: "First paragraph.\n\nSecond paragraph.",
            primaryPage: page,
            capturedAt: capturedAt
        )

        let body = MarkExportSnapshotSection.append(
            to: "## Highlights\n\n- Useful article.",
            snapshotSection: snapshot
        )

        #expect(body.contains("## Highlights"))
        #expect(body.contains("## Snapshot"))
        #expect(body.contains("Captured from Chrome"))
        #expect(body.contains("[Original page](https://example.com/blog/example-article)"))
        #expect(body.contains("First paragraph."))
        #expect(body.hasSuffix("Second paragraph."))
    }

    @Test func snapshotSectionStripsModelGeneratedSnapshot() {
        let page = ConversationPageReferences.PageReference(
            title: "Example Article",
            url: "https://example.com/blog/example-article",
            browserName: "Chrome"
        )
        let snapshot = MarkExportSnapshotSection.build(
            extractedText: "Captured article body.",
            primaryPage: page,
            capturedAt: nil
        )

        let body = MarkExportSnapshotSection.append(
            to: """
            ## Highlights

            - Summary

            ## Snapshot

            - Model paraphrase that should be removed
            """,
            snapshotSection: snapshot
        )

        #expect(body.contains("Captured article body."))
        #expect(!body.contains("Model paraphrase"))
        #expect(body.components(separatedBy: "## Snapshot").count == 2)
    }

    @Test func primaryPageCapturePrefersOldestContextStackPage() {
        let oldest = BrowserPageContext(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 10),
            url: "https://example.com/blog/post",
            pageTitle: "Post",
            extractedText: "Oldest captured body.",
            browserName: "Chrome"
        )
        let newest = BrowserPageContext(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 20),
            url: "https://example.com/other",
            pageTitle: "Other",
            extractedText: "Other body.",
            browserName: "Chrome"
        )
        let primaryPage = ConversationPageReferences.PageReference(
            title: "Post",
            url: "https://example.com/blog/post",
            browserName: "Chrome"
        )

        let capture = ConversationPageReferences.primaryPageCapture(
            primaryPage: primaryPage,
            browserPageContexts: [newest, oldest],
            contextualMessages: [],
            conversationMessages: []
        )

        #expect(capture?.extractedText == "Oldest captured body.")
        #expect(capture?.capturedAt == oldest.createdAt)
    }

    // MARK: - Search command

    @Test func searchCommandMatchesBareKeyword() {
        #expect(SearchCommand.parse(from: "/search")?.query == "")
        #expect(SearchCommand.parse(from: "  /search  ")?.query == "")
    }

    @Test func searchCommandMatchesWithQuery() {
        #expect(SearchCommand.parse(from: "/search what did I save about MLX?")?.query == "what did I save about MLX?")
    }

    @Test func searchCommandRejectsPartialKeywordMatches() {
        #expect(SearchCommand.parse(from: "/searching notes") == nil)
        #expect(SearchCommand.parse(from: "please /search later") == nil)
    }

    @Test func registryParsesSearchCommand() {
        if case let .search(parsed) = ComposerCommandRegistry.parse(from: "/search mlx agents") {
            #expect(parsed.query == "mlx agents")
        } else {
            Issue.record("Expected search command")
        }
    }

    @Test func searchResultMessageRoundTripPreservesSources() {
        let sources = [
            SearchResultSource(
                filePath: "/tmp/note.md",
                title: "MLX Agents",
                excerpt: "Local stack overview.",
                section: "Highlights"
            )
        ]
        let message = SearchResultMessage.messageText(answer: "You saved one note.", sources: sources)
        let parsed = SearchResultMessage.parse(from: message)

        #expect(parsed?.answer == "You saved one note.")
        #expect(parsed?.sources == sources)
    }

    @Test func searchConfigurationRequiresAgentModeAndMarkFolder() {
        let disabled = SearchConfiguration(isAgentModeEnabled: false)
        let mark = MarkExportConfiguration(isEnabled: true, exportFolderPath: "/tmp/bookmarks")

        #expect(disabled.validationError(markConfiguration: mark)?.contains("Agent mode") == true)

        let enabled = SearchConfiguration(isAgentModeEnabled: true)
        let missingFolder = MarkExportConfiguration(isEnabled: false, exportFolderPath: "")

        #expect(enabled.validationError(markConfiguration: missingFolder)?.contains("Mark with /mark") == true)
    }

    @Test func searchSidecarLLMConfigurationMapsConversationSettings() {
        var configuration = ConversationConfiguration.defaultValue
        configuration.provider = .ollama
        configuration.ollamaBaseURL = "http://localhost:11434"
        configuration.ollamaModel = "gemma4:e4b-mlx"

        let mapped = SearchSidecarLLMConfiguration(configuration: configuration)
        #expect(mapped.provider == "ollama")
        #expect(mapped.baseURL == "http://localhost:11434")
        #expect(mapped.model == "gemma4:e4b-mlx")
    }

    @Test func searchSidecarIndexRequestEncodesCorpusRoot() throws {
        let request = SearchSidecarIndexRequest(corpusRoot: "/tmp/bookmarks")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["corpus_root"] as? String == "/tmp/bookmarks")
    }

    @Test func markPromptEnsuringGenerationInstructionsAppendsMissingRules() {
        let customPrompt = "Write a short bookmark."
        let ensured = MarkExportPrompts.ensuringGenerationInstructions(customPrompt)

        #expect(ensured.contains("Write a short bookmark."))
        #expect(ensured.contains(MarkExportPrompts.whyISavedThisRuleMarker))
        #expect(ensured.contains(MarkExportPrompts.jsonOutputContractMarker))
        #expect(ensured.contains("## Why I saved this"))
    }

    @Test func markPromptEnsuringGenerationInstructionsDoesNotDuplicateDefaultPrompt() {
        let ensured = MarkExportPrompts.ensuringGenerationInstructions(MarkExportPrompts.defaultBase)
        let whyMarkerCount = ensured.components(separatedBy: MarkExportPrompts.whyISavedThisRuleMarker).count - 1
        let jsonMarkerCount = ensured.components(separatedBy: MarkExportPrompts.jsonOutputContractMarker).count - 1

        #expect(whyMarkerCount == 1)
        #expect(jsonMarkerCount == 1)
    }
}
