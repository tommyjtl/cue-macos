import Foundation

enum ObsidianNoteWriterError: LocalizedError {
    case invalidTitle
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Cue could not derive a title for the note."
        case let .writeFailed(message):
            return message
        }
    }
}

struct ObsidianNoteWriter {
    enum ExportKind: Equatable {
        case saveConversation
        case markPage(host: String)
        case markConversation
    }

    struct Reference: Equatable {
        let title: String
        let url: String
    }

    struct WriteInput: Equatable {
        let title: String
        let body: String
        let sourceURL: String?
        let references: [Reference]
        let createdAt: Date
        let exportFolderURL: URL
        let exportKind: ExportKind
        let tags: [String]?

        init(
            title: String,
            body: String,
            sourceURL: String?,
            references: [Reference],
            createdAt: Date,
            exportFolderURL: URL,
            exportKind: ExportKind = .saveConversation,
            tags: [String]? = nil
        ) {
            self.title = title
            self.body = body
            self.sourceURL = sourceURL
            self.references = references
            self.createdAt = createdAt
            self.exportFolderURL = exportFolderURL
            self.exportKind = exportKind
            self.tags = tags
        }
    }

    struct WriteResult: Equatable {
        let fileURL: URL
        let title: String
    }

    func write(_ input: WriteInput) throws -> WriteResult {
        let trimmedTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ObsidianNoteWriterError.invalidTitle
        }

        let dateFolderName = Self.dateFolderFormatter.string(from: input.createdAt)
        let dateDirectory = input.exportFolderURL.appendingPathComponent(dateFolderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        } catch {
            throw ObsidianNoteWriterError.writeFailed("Cue could not create the date folder: \(error.localizedDescription)")
        }

        let fileName = Self.fileName(from: trimmedTitle, exportKind: input.exportKind)
        var fileURL = dateDirectory.appendingPathComponent(fileName, isDirectory: false)

        var collisionIndex = 2
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = dateDirectory.appendingPathComponent("\(baseName)-\(collisionIndex).md", isDirectory: false)
            collisionIndex += 1
        }

        let markdown = Self.buildMarkdown(
            title: trimmedTitle,
            body: input.body,
            sourceURL: input.sourceURL,
            references: input.references,
            createdAt: input.createdAt,
            exportKind: input.exportKind,
            tags: input.tags
        )

        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ObsidianNoteWriterError.writeFailed("Cue could not write the note: \(error.localizedDescription)")
        }

        return WriteResult(fileURL: fileURL, title: trimmedTitle)
    }

    static func fileName(from title: String, exportKind: ExportKind = .saveConversation) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch exportKind {
            case .saveConversation:
                return "note.md"
            case .markPage, .markConversation:
                return "mark.md"
            }
        }

        let sanitized = sanitizedTitleBase(from: trimmed)
        guard !sanitized.isEmpty else {
            switch exportKind {
            case .saveConversation:
                return "note.md"
            case .markPage, .markConversation:
                return "mark.md"
            }
        }

        switch exportKind {
        case .saveConversation:
            return "\(String(sanitized.prefix(120))).md"
        case .markPage, .markConversation:
            return "\(String(sanitized.prefix(80))).md"
        }
    }

    private static func sanitizedTitleBase(from title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?*\"<>|`{}")
        let sanitizedScalars = title.unicodeScalars.map { scalar -> Character in
            if invalidCharacters.contains(scalar) {
                return "-"
            }
            return Character(scalar)
        }

        return String(sanitizedScalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
    }

    private static func buildMarkdown(
        title: String,
        body: String,
        sourceURL: String?,
        references: [Reference],
        createdAt: Date,
        exportKind: ExportKind,
        tags: [String]?
    ) -> String {
        let tagValues: [String]
        switch exportKind {
        case .saveConversation:
            tagValues = tags ?? ["cue", "save"]
        case .markPage, .markConversation:
            tagValues = tags ?? [MarkExportTagVocabulary.systemTag]
        }
        let tagsLine = "[\(tagValues.joined(separator: ", "))]"

        var frontmatterLines = [
            "---",
            "title: \"\(yamlEscaped(title))\"",
            "created: \(iso8601Formatter.string(from: createdAt))",
            "tags: \(tagsLine)"
        ]

        if let sourceURL, !sourceURL.isEmpty {
            frontmatterLines.append("source: \"\(yamlEscaped(sourceURL))\"")
        }

        if case .markPage(let host) = exportKind, !host.isEmpty {
            frontmatterLines.append("domain: \"\(yamlEscaped(host))\"")
        }

        frontmatterLines.append("---")

        let noteBody: String
        switch exportKind {
        case .saveConversation:
            noteBody = appendReferencesSection(to: body, references: references)
        case .markPage, .markConversation:
            noteBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmedBody = noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return frontmatterLines.joined(separator: "\n") + "\n"
        }

        return frontmatterLines.joined(separator: "\n") + "\n\n" + trimmedBody + "\n"
    }

    private static func appendReferencesSection(to body: String, references: [Reference]) -> String {
        guard !references.isEmpty else {
            return body
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.localizedCaseInsensitiveContains("## References") {
            return trimmedBody
        }

        let referenceLines = references.map { reference in
            "- [\(reference.title)](\(reference.url))"
        }
        let referencesSection = "## References\n\n" + referenceLines.joined(separator: "\n")

        if trimmedBody.isEmpty {
            return referencesSection
        }

        return trimmedBody + "\n\n" + referencesSection
    }

    private static func yamlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static var dateFolderFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }


    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
