import AppKit
import Foundation

enum ObsidianSavedNoteMessage {
    static let confirmationPrefix = "Saved to Obsidian:"

    static func confirmationText(filePath: String) -> String {
        "\(confirmationPrefix) `\(filePath)`"
    }

    static func savedNoteFileURL(from messageText: String) -> URL? {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(confirmationPrefix) else {
            return nil
        }

        let pattern = #"Saved to Obsidian:\s*`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              match.numberOfRanges > 1,
              let pathRange = Range(match.range(at: 1), in: trimmed)
        else {
            return nil
        }

        let path = String(trimmed[pathRange])
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
