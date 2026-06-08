import Foundation

enum MarkExportBodySanitizer {
    private static let personalSectionHeadings = [
        "why i saved this",
        "why i'm saving this",
        "my notes",
        "my take",
        "my angle"
    ]

    /// Page-only bookmarks (/mark with no hint and no real conversation) should not invent user motive or opinions.
    static func sanitizeForPageOnlyBookmark(_ body: String) -> String {
        stripPersonalSections(from: body)
    }

    /// Guarantees a bookmark has readable body content when the model returns only a title or empty sections.
    static func ensureMinimumContent(
        _ body: String,
        primaryPage: ConversationPageReferences.PageReference,
        userHint: String
    ) -> String {
        if hasSubstantiveContent(body) {
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return minimumContentFallback(primaryPage: primaryPage, userHint: userHint)
    }

    static func hasSubstantiveContent(_ body: String) -> Bool {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
                continue
            }

            return true
        }

        return false
    }

    private static func minimumContentFallback(
        primaryPage: ConversationPageReferences.PageReference,
        userHint: String
    ) -> String {
        var bullets = [
            "[\(primaryPage.title)](\(primaryPage.url))"
        ]

        let trimmedHint = userHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty {
            bullets.append("Bookmark focus: \(trimmedHint)")
        } else {
            bullets.append("Saved from Cue for later reference.")
        }

        let bulletLines = bullets.map { "- \($0)" }.joined(separator: "\n")
        return "## Highlights\n\n\(bulletLines)"
    }

    private static func stripPersonalSections(from body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var leadLines: [String] = []
        var sections: [(heading: String, content: String)] = []
        var currentHeading: String?
        var currentLines: [String] = []

        func flushSection() {
            guard let heading = currentHeading else {
                return
            }

            sections.append((heading: heading, content: currentLines.joined(separator: "\n")))
            currentHeading = nil
            currentLines = []
        }

        for line in trimmed.components(separatedBy: .newlines) {
            if let heading = markdownHeadingTitle(in: line) {
                flushSection()
                currentHeading = heading
                continue
            }

            if currentHeading == nil {
                leadLines.append(line)
            } else {
                currentLines.append(line)
            }
        }

        flushSection()

        let keptSections = sections.filter { section in
            !personalSectionHeadings.contains(section.heading.lowercased())
        }

        var parts: [String] = []
        let lead = leadLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty {
            parts.append(lead)
        }

        for section in keptSections {
            let content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                parts.append("## \(section.heading)")
            } else {
                parts.append("## \(section.heading)\n\n\(content)")
            }
        }

        return parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownHeadingTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("## ") else {
            return nil
        }

        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
