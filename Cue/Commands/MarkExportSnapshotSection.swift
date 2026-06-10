import Foundation

enum MarkExportSnapshotSection {
    static let maxSnapshotCharacters = 20_000

    static func build(
        extractedText: String,
        primaryPage: ConversationPageReferences.PageReference,
        capturedAt: Date?
    ) -> String {
        let metadata = metadataLine(
            browserName: primaryPage.browserName,
            url: primaryPage.url,
            capturedAt: capturedAt
        )
        let body = truncatedSnapshotBody(from: extractedText)

        return "## Snapshot\n\n\(metadata)\n\n\(body)"
    }

    static func append(to body: String, snapshotSection: String) -> String {
        let withoutModelSnapshot = stripExistingSnapshotSection(from: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if withoutModelSnapshot.isEmpty {
            return snapshotSection
        }

        return "\(withoutModelSnapshot)\n\n\(snapshotSection)"
    }

    static func stripExistingSnapshotSection(from body: String) -> String {
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
            section.heading.lowercased() != "snapshot"
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

        return parts.joined(separator: "\n\n")
    }

    private static func metadataLine(
        browserName: String,
        url: String,
        capturedAt: Date?
    ) -> String {
        if let capturedAt {
            return "_Captured from \(browserName) on \(captureDateFormatter.string(from: capturedAt)). [Original page](\(url))._"
        }

        return "_Captured from \(browserName). [Original page](\(url))._"
    }

    private static func truncatedSnapshotBody(from extractedText: String) -> String {
        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxSnapshotCharacters else {
            return trimmed
        }

        let prefix = String(trimmed.prefix(maxSnapshotCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return "\(prefix)\n\n… [Snapshot truncated at capture — \(trimmed.count) characters total.]"
    }

    private static func markdownHeadingTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("## ") else {
            return nil
        }

        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
