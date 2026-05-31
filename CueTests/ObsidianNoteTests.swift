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
                references: [],
                createdAt: createdAt,
                exportFolderURL: rootDirectory
            )
        )

        #expect(result.title == "LocalStorage Pitfalls")
        #expect(result.fileURL.path.contains("2026-05-30"))
        #expect(result.fileURL.lastPathComponent == "14-32 - localstorage-pitfalls.md")

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        #expect(markdown.contains("title: \"LocalStorage Pitfalls\""))
        #expect(markdown.contains("source: \"https://example.com/article\""))
        #expect(markdown.contains("## Takeaways"))
    }

    @Test func noteWriterSlugifiesTitles() {
        #expect(ObsidianNoteWriter.slugify("Hello, World!") == "hello-world")
        #expect(ObsidianNoteWriter.slugify("   ") == "note")
    }
}
