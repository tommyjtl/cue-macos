import Foundation
import Testing
@testable import Cue

struct ObsidianNoteTests {

    @Test func noteCommandMatchesBareNoteKeyword() {
        #expect(NoteCommand.parse(from: "/note")?.userHint == "")
        #expect(NoteCommand.parse(from: "  /note  ")?.userHint == "")
    }

    @Test func noteCommandMatchesNoteWithHint() {
        #expect(NoteCommand.parse(from: "/note focus on localStorage pitfalls")?.userHint == "focus on localStorage pitfalls")
    }

    @Test func noteCommandMatchesNotesAlias() {
        #expect(NoteCommand.parse(from: "/notes")?.userHint == "")
        #expect(NoteCommand.parse(from: "/notes key naming")?.userHint == "key naming")
    }

    @Test func noteCommandRejectsPartialKeywordMatches() {
        #expect(NoteCommand.parse(from: "/notebook") == nil)
        #expect(NoteCommand.parse(from: "please /note later") == nil)
    }

    @Test func noteCommandHighlightsLeadingKeywordRange() {
        #expect(NoteCommand.leadingKeywordRange(in: "/note focus")?.lowerBound == "/note focus".startIndex)
        #expect(NoteCommand.leadingKeywordRange(in: "/notebook") == nil)
    }

    @Test func noteWriterCreatesDateFolderAndMarkdownFile() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-obsidian-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

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
                exportFolderURL: rootDirectory
            )
        )

        #expect(result.title == "LocalStorage Pitfalls")
        #expect(result.fileURL.path.contains("2026-05-30"))
        #expect(result.fileURL.lastPathComponent == "LocalStorage Pitfalls.md")

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(markdown.contains("title: \"LocalStorage Pitfalls\""))
        #expect(markdown.contains("source: \"https://example.com/article\""))
        #expect(markdown.contains("## Takeaways"))
        #expect(markdown.contains("## References"))
        #expect(markdown.contains("[Example Article](https://example.com/article)"))
    }

    @Test func noteWriterAppendsReferencesSection() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-obsidian-ref-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let writer = ObsidianNoteWriter()
        let result = try writer.write(
            ObsidianNoteWriter.WriteInput(
                title: "Test Note",
                body: "## Takeaways\n\n- One thing learned",
                sourceURL: "https://example.com/page",
                references: [
                    ObsidianNoteWriter.Reference(title: "Example Page", url: "https://example.com/page")
                ],
                createdAt: Date(),
                exportFolderURL: rootDirectory
            )
        )

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(markdown.contains("## References"))
        #expect(markdown.contains("[Example Page](https://example.com/page)"))
    }

    @Test func collectReferencesUsesPersistedConversationPages() {
        let references = ObsidianNoteService.collectReferences(
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
                ConversationMessageDTO(role: .user, text: "/note")
            ]
        )

        #expect(references.count == 1)
        #expect(references[0].url == "https://www.youtube.com/watch?v=example")
        #expect(references[0].title == "Chinese comedy roast compilation")
    }

    @Test func noteWriterSanitizesFileNames() {
        #expect(ObsidianNoteWriter.fileName(from: "Hello, World!") == "Hello, World!.md")
        #expect(ObsidianNoteWriter.fileName(from: "   ") == "note.md")
        #expect(ObsidianNoteWriter.fileName(from: "Bad/Name:Here") == "Bad-Name-Here.md")
        #expect(ObsidianNoteWriter.fileName(from: "My `code` note") == "My -code- note.md")
    }

    @Test func savedNoteMessageParsesFilePath() {
        let path = "/Users/example/Obsidian/Vault/2026-06-03/Note title.md"
        let message = ObsidianSavedNoteMessage.confirmationText(filePath: path)

        #expect(ObsidianSavedNoteMessage.savedNoteFileURL(from: message)?.path == path)
        #expect(ObsidianSavedNoteMessage.savedNoteFileURL(from: "Saved to Obsidian.") == nil)
    }

    @Test func savedNoteMessageParsesPathWithBackticksInLegacyFormat() {
        let path = "/Users/example/Vault/My `code` note.md"
        let legacyMessage = "Saved to Obsidian: `\(path)`"

        #expect(ObsidianSavedNoteMessage.savedNoteFileURL(from: legacyMessage)?.path == path)
    }

    @Test func openURLUsesObsidianURIWithNewTab() {
        let fileURL = URL(fileURLWithPath: "/Users/example/Vault/note.md")
        let openURL = ObsidianNoteOpener.openURL(for: fileURL)

        #expect(openURL?.scheme == "obsidian")
        #expect(openURL?.host == "open")
        #expect(openURL?.absoluteString.contains("paneType=tab") == true)
        #expect(openURL?.absoluteString.contains("path=") == true)
    }

    @Test func exportConfigurationRequiresEnabledToggle() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-obsidian-config-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let disabledConfiguration = ObsidianExportConfiguration(
            isEnabled: false,
            exportFolderPath: rootDirectory.path
        )
        #expect(disabledConfiguration.validationError == "Enable \"Save /note to Obsidian\" in Settings.")

        let enabledConfiguration = ObsidianExportConfiguration(
            isEnabled: true,
            exportFolderPath: rootDirectory.path
        )
        #expect(enabledConfiguration.validationError == nil)
    }
}
