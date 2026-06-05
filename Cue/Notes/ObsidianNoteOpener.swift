import AppKit
import Foundation

enum ObsidianNoteOpener {
    static func openInNewTab(fileURL: URL) {
        guard let url = openURL(for: fileURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func openURL(for fileURL: URL) -> URL? {
        let standardizedPath = fileURL.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: standardizedPath) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "path", value: standardizedPath),
            URLQueryItem(name: "paneType", value: "tab"),
        ]
        return components.url
    }
}
