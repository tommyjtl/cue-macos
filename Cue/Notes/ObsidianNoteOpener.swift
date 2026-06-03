import AppKit
import Foundation

enum ObsidianSavedNoteMessage {
    static let confirmationPrefix = "Saved to Obsidian:"

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
            // Legacy messages wrapped the path in backticks; use the last backtick so
            // paths that still contain backticks (old filenames) parse correctly.
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

enum ObsidianNoteOpener {
    static func openInNewTab(fileURL: URL) {
        guard let url = openURL(for: fileURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func openURL(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: fileURL.path),
            URLQueryItem(name: "paneType", value: "tab"),
        ]
        return components.url
    }
}
