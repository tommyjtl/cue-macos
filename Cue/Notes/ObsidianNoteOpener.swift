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
