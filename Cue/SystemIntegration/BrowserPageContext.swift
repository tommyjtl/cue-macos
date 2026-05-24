import Foundation

struct BrowserPageContext: Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    /// The committed URL of the tab at capture time.
    let url: String
    let pageTitle: String
    /// Readability-extracted plain text from the page.
    let extractedText: String
    let browserName: String

    /// Shortest human-readable label: host only, without www.
    var displayDomain: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
