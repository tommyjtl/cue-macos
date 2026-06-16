import Foundation

enum MarkGeneratedContentParser {
    struct Parsed: Equatable {
        let title: String
        let body: String
    }

    static func parse(_ responseText: String, fallbackTitle: String = "") throws -> Parsed {
        let normalized = stripMarkdownFences(
            from: responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !normalized.isEmpty else {
            throw MarkGeneratedContentParseFailure.emptyResponse
        }

        let parsed = try parseJSONPayload(from: normalized)

        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty
            ? fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : title

        guard !resolvedTitle.isEmpty else {
            throw MarkGeneratedContentParseFailure.emptyTitle
        }

        guard MarkExportBodySanitizer.hasSubstantiveContent(body) else {
            throw MarkGeneratedContentParseFailure.emptyBody
        }

        return Parsed(title: resolvedTitle, body: body)
    }

    private static func parseJSONPayload(from text: String) throws -> Parsed {
        let jsonText = extractJSONPayload(from: text)
        guard jsonText.hasPrefix("{"),
              let data = jsonText.data(using: .utf8) else {
            throw MarkGeneratedContentParseFailure.invalidJSON("Response is not a JSON object.")
        }

        struct GeneratedNoteContent: Decodable {
            let title: String
            let body: String
        }

        do {
            let decoded = try JSONDecoder().decode(GeneratedNoteContent.self, from: data)
            return Parsed(title: decoded.title, body: decoded.body)
        } catch {
            throw MarkGeneratedContentParseFailure.invalidJSON(error.localizedDescription)
        }
    }

    private static func extractJSONPayload(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "json" {
                lines.removeFirst()
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            return String(trimmed[start ... end])
        }

        return trimmed
    }

    private static func stripMarkdownFences(from text: String) -> String {
        guard text.hasPrefix("```") else {
            return text
        }

        var lines = text.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
            lines.removeLast()
        }
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["markdown", "md", "json"].contains(first) {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
