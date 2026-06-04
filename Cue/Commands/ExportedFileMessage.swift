import Foundation

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
