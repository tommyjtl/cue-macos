import Foundation
import Testing
@testable import Cue

struct CommandExportTests {

    // MARK: - Save command

    @Test func saveCommandMatchesBareKeyword() {
        #expect(SaveCommand.parse(from: "/save")?.userHint == "")
        #expect(SaveCommand.parse(from: "/note")?.userHint == "")
        #expect(SaveCommand.parse(from: "  /note  ")?.userHint == "")
    }

    @Test func saveCommandMatchesWithHint() {
        #expect(SaveCommand.parse(from: "/save focus on localStorage pitfalls")?.userHint == "focus on localStorage pitfalls")
        #expect(SaveCommand.parse(from: "/note focus on localStorage pitfalls")?.userHint == "focus on localStorage pitfalls")
    }

    @Test func saveCommandMatchesNotesAlias() {
        #expect(SaveCommand.parse(from: "/notes")?.userHint == "")
        #expect(SaveCommand.parse(from: "/notes key naming")?.userHint == "key naming")
    }

    @Test func saveCommandRejectsPartialKeywordMatches() {
        #expect(SaveCommand.parse(from: "/notebook") == nil)
        #expect(SaveCommand.parse(from: "please /note later") == nil)
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
        #expect(SaveCommand.leadingKeywordRange(in: "/note focus")?.lowerBound == "/note focus".startIndex)
        #expect(MarkCommand.leadingKeywordRange(in: "// blog")?.lowerBound == "// blog".startIndex)
        #expect(ComposerCommandRegistry.leadingKeywordRange(in: "/notebook") == nil)
    }

    // MARK: - Mark command

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

    @Test func markWriterUsesTitleAndHostFileName() {
        let fileName = ObsidianNoteWriter.fileName(
            from: "Supertonic ONNX",
            exportKind: .markPage(host: "github.com")
        )
        #expect(fileName == "Supertonic ONNX--github.com.md")
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

    @Test func exportConfigurationValidation() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-config-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let disabledSave = SaveExportConfiguration(isEnabled: false, exportFolderPath: rootDirectory.path)
        #expect(
            disabledSave.validationError(enabledMessage: "Enable save.") == "Enable save."
        )

        let enabledSave = SaveExportConfiguration(isEnabled: true, exportFolderPath: rootDirectory.path)
        #expect(enabledSave.validationError(enabledMessage: "Enable save.") == nil)

        let disabledMark = MarkExportConfiguration(isEnabled: false, exportFolderPath: rootDirectory.path)
        #expect(disabledMark.validationError != nil)

        let enabledMark = MarkExportConfiguration(isEnabled: true, exportFolderPath: rootDirectory.path)
        #expect(enabledMark.validationError == nil)
    }
}
