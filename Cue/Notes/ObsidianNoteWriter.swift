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

        let timePrefix = Self.timePrefixFormatter.string(from: input.createdAt)
        let slug = Self.slugify(trimmedTitle)
        var fileURL = dateDirectory.appendingPathComponent("\(timePrefix) - \(slug).md", isDirectory: false)

        var collisionIndex = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = dateDirectory.appendingPathComponent("\(timePrefix) - \(slug)-\(collisionIndex).md", isDirectory: false)
            collisionIndex += 1
        }

        let markdown = Self.buildMarkdown(
            title: trimmedTitle,
            body: input.body,
            sourceURL: input.sourceURL,
            createdAt: input.createdAt
        )

        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ObsidianNoteWriterError.writeFailed("Cue could not write the note: \(error.localizedDescription)")
        }

        return WriteResult(fileURL: fileURL, title: trimmedTitle)
    }

    static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            if character.isWhitespace || character == "-" {
                return "-"
            }
            return "-"
        }

        let collapsed = String(allowed)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if collapsed.isEmpty {
            return "note"
        }

        return String(collapsed.prefix(60))
    }

    private static func buildMarkdown(
        title: String,
        body: String,
        sourceURL: String?,
        createdAt: Date
    ) -> String {
        var frontmatterLines = [
            "---",
            "title: \"\(yamlEscaped(title))\"",
            "created: \(iso8601Formatter.string(from: createdAt))",
            "tags: [cue]"
        ]

        if let sourceURL, !sourceURL.isEmpty {
            frontmatterLines.append("source: \"\(yamlEscaped(sourceURL))\"")
        }

        frontmatterLines.append("---")

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return frontmatterLines.joined(separator: "\n") + "\n"
        }

        return frontmatterLines.joined(separator: "\n") + "\n\n" + trimmedBody + "\n"
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

    private static var timePrefixFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH-mm"
        return formatter
    }

    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
