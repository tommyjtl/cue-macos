import Foundation

enum ConversationJSONExportMessage {
    nonisolated static let confirmationPrefix = "Exported conversation:"

    static func confirmationText(filePath: String) -> String {
        "\(confirmationPrefix) \(filePath)"
    }

    static func exportedFileURL(from messageText: String) -> URL? {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(confirmationPrefix) else {
            return nil
        }

        let path = trimmed.dropFirst(confirmationPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: String(path))
    }
}

enum MarkExportFailureMessage {
    nonisolated static let prefix = "cue-mark-export-failure:"

    static func messageText(userMessageID: UUID, errorDescription: String) -> String {
        "\(prefix)\(userMessageID.uuidString)\n\(errorDescription)"
    }

    static func parse(from messageText: String) -> (userMessageID: UUID, errorDescription: String)? {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else {
            return nil
        }

        let remainder = trimmed.dropFirst(prefix.count)
        guard let newlineIndex = remainder.firstIndex(of: "\n") else {
            return nil
        }

        let idString = String(remainder[..<newlineIndex])
        guard let userMessageID = UUID(uuidString: idString) else {
            return nil
        }

        let errorDescription = String(remainder[remainder.index(after: newlineIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !errorDescription.isEmpty else {
            return nil
        }

        return (userMessageID, errorDescription)
    }
}

enum ObsidianSavedNoteMessage {
    nonisolated static let confirmationPrefix = "Saved to Obsidian:"

    static func confirmationText(filePath: String) -> String {
        "\(confirmationPrefix) \(filePath)"
    }

    static func savedNoteFileURL(from messageText: String) -> URL? {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(confirmationPrefix) else {
            return nil
        }

        let remainder = trimmed.dropFirst(confirmationPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let path: String
        if remainder.hasPrefix("`"),
           let closingBacktick = remainder.lastIndex(of: "`"),
           closingBacktick > remainder.startIndex {
            path = String(remainder[remainder.index(after: remainder.startIndex)..<closingBacktick])
        } else {
            path = String(remainder)
        }

        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}
