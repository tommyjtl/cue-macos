import Foundation

enum MarkExportSnapshotEligibility {
    static let minimumExtractedTextLength = 400

    static func shouldIncludeSnapshot(
        primaryPage: ConversationPageReferences.PageReference,
        extractedText: String,
        userHint: String
    ) -> Bool {
        let trimmedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        if userHintRequestsSnapshot(userHint) {
            return true
        }

        if MarkExportDefaultSynthesisInstruction.isYouTubeURL(primaryPage.url) {
            return false
        }

        guard trimmedText.count >= minimumExtractedTextLength else {
            return false
        }

        if looksLikeHomepage(url: primaryPage.url) {
            return false
        }

        return true
    }

    private static func userHintRequestsSnapshot(_ hint: String) -> Bool {
        let lower = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else {
            return false
        }

        let triggers = [
            "full article",
            "archive",
            "snapshot",
            "preserve",
            "verbatim",
            "original text",
            "save the post",
            "save this post"
        ]

        return triggers.contains { lower.contains($0) }
    }

    private static func looksLikeHomepage(url: String) -> Bool {
        guard let parsed = URL(string: url) else {
            return false
        }

        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return path.isEmpty || path == "home" || path == "index.html" || path == "index.htm"
    }
}
