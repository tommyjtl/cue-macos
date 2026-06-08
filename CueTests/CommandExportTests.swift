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

    @Test func markGeneratedContentParserUsesFirstLineAsTitle() throws {
        let response = """
        Fallow — codebase intelligence for TypeScript
        ## Highlights
        - Useful for large JS repos
        """

        let parsed = try MarkGeneratedContentParser.parse(response)
        #expect(parsed.title == "Fallow — codebase intelligence for TypeScript")
        #expect(parsed.body.hasPrefix("## Highlights"))
    }

    @Test func markGeneratedContentParserIgnoresTagsLine() throws {
        let parsed = try MarkGeneratedContentParser.parse("""
        Adversarial Security Evaluation
        Tags: article, research, reference
        ## Highlights
        - Field report on security testing
        """)

        #expect(parsed.title == "Adversarial Security Evaluation")
        #expect(parsed.body.hasPrefix("## Highlights"))
        #expect(!parsed.body.localizedCaseInsensitiveContains("Tags:"))
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

    @Test func markGeneratedContentParserStripsHeadingPrefixFromTitle() throws {
        let parsed = try MarkGeneratedContentParser.parse("""
        # Startup launch notes
        ## Why I saved this
        Comparing against Linear.
        """)

        #expect(parsed.title == "Startup launch notes")
        #expect(parsed.body.contains("## Why I saved this"))
    }

    @Test func markGeneratedContentParserAcceptsJSONResponse() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            {"title":"Fallow - Codebase Intelligence for TypeScript & JavaScript","body":"## Highlights\\n\\n- Useful for large repos"}
            """,
            fallbackTitle: "Fallow"
        )

        #expect(parsed.title == "Fallow - Codebase Intelligence for TypeScript & JavaScript")
        #expect(parsed.body.hasPrefix("## Highlights"))
    }

    @Test func markGeneratedContentParserAcceptsLegacyDelimiterFormat() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            {-title-Fallow - Codebase Intelligence for TypeScript & JavaScript-,-body-## Highlights

            - Field report
            """,
            fallbackTitle: "Fallow"
        )

        #expect(parsed.title == "Fallow - Codebase Intelligence for TypeScript & JavaScript")
        #expect(parsed.body.contains("## Highlights"))
    }

    @Test func markGeneratedContentParserFallsBackWhenFirstLineIsJSONBlob() throws {
        let parsed = try MarkGeneratedContentParser.parse(
            """
            {"title":"Broken","body":"## Highlights\\n- One"}
            """,
            fallbackTitle: "Page title from browser"
        )

        #expect(parsed.title == "Broken")
    }

    @Test func markWriterSanitizesBraceCharactersInFileName() {
        #expect(
            ObsidianNoteWriter.fileName(
                from: "{title-Bad-,-body-##",
                exportKind: .markPage(host: "example.com")
            ) == "title-Bad-,-body-##.md"
        )
    }

    @Test func markBodySanitizerEnsuresMinimumContentWhenBodyIsEmpty() {
        let body = MarkExportBodySanitizer.ensureMinimumContent(
            "",
            primaryPage: ConversationPageReferences.PageReference(
                title: "Augment – Buddy Bindery & Press",
                url: "https://example.com/augment",
                browserName: "Safari"
            ),
            userHint: ""
        )

        #expect(body.contains("## Highlights"))
        #expect(body.contains("[Augment – Buddy Bindery & Press](https://example.com/augment)"))
        #expect(body.contains("Saved from Cue for later reference."))
    }

    @Test func markBodySanitizerEnsuresMinimumContentIncludesHint() {
        let body = MarkExportBodySanitizer.ensureMinimumContent(
            "## Highlights",
            primaryPage: ConversationPageReferences.PageReference(
                title: "Example Article",
                url: "https://example.com/article",
                browserName: "Chrome"
            ),
            userHint: "incorporate the major purpose of this article"
        )

        #expect(body.contains("Bookmark focus: incorporate the major purpose of this article"))
    }

    @Test func markBodySanitizerPreservesSubstantiveModelBody() {
        let original = """
        ## Highlights

        - Useful methodology for security testing
        """

        let body = MarkExportBodySanitizer.ensureMinimumContent(
            original,
            primaryPage: ConversationPageReferences.PageReference(
                title: "Security Field Report",
                url: "https://example.com/report",
                browserName: "Safari"
            ),
            userHint: ""
        )

        #expect(body == original)
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

    @Test func markBodySanitizerStripsPersonalSectionsForPageOnlyBookmark() {
        let sanitized = MarkExportBodySanitizer.sanitizeForPageOnlyBookmark(
            """
            ## Highlights

            - A forthcoming essay collection.

            ## My notes

            This is a call for thoughtful contributions.

            ## Why I saved this

            I want to revisit this later.
            """
        )

        #expect(sanitized.contains("## Highlights"))
        #expect(!sanitized.localizedCaseInsensitiveContains("## My notes"))
        #expect(!sanitized.localizedCaseInsensitiveContains("## Why I saved this"))
    }

    @Test func markGeneratedContentParserStripsMarkdownFences() throws {
        let parsed = try MarkGeneratedContentParser.parse("""
        ```markdown
        Page bookmark title
        ## Highlights
        - Item one
        ```
        """)

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
            MarkCommand.hasMarkablePage(
                browserPageContexts: [page],
                contextualMessages: [],
                conversationMessages: []
            )
        )
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
}
