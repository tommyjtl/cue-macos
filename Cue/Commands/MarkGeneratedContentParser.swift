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
            throw MarkExportServiceError.invalidModelResponse
        }

        guard let parsed = parseJSONPayload(from: normalized) else {
            throw MarkExportServiceError.invalidModelResponse
        }

        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty
            ? fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : title

        guard !resolvedTitle.isEmpty else {
            throw MarkExportServiceError.invalidModelResponse
        }

        guard MarkExportBodySanitizer.hasSubstantiveContent(body) else {
            throw MarkExportServiceError.invalidModelResponse
        }

        return Parsed(title: resolvedTitle, body: body)
    }

    private static func parseJSONPayload(from text: String) -> Parsed? {
        let jsonText = extractJSONPayload(from: text)
        guard jsonText.hasPrefix("{"),
              let data = jsonText.data(using: .utf8) else {
            return nil
        }

        struct GeneratedNoteContent: Decodable {
            let title: String
            let body: String
        }

        guard let decoded = try? JSONDecoder().decode(GeneratedNoteContent.self, from: data) else {
            return nil
        }

        return Parsed(title: decoded.title, body: decoded.body)
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
