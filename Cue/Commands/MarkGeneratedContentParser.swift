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

        if let parsed = parseJSONPayload(from: normalized) {
            return finalize(parsed, fallbackTitle: fallbackTitle, rawText: normalized)
        }

        if let parsed = parseLegacyDelimiterFormat(from: normalized) {
            return finalize(parsed, fallbackTitle: fallbackTitle, rawText: normalized)
        }

        let markdownParsed = try parseMarkdownLines(from: normalized)
        if isValidTitle(markdownParsed.title) {
            return markdownParsed
        }

        if let parsed = parseJSONPayload(from: markdownParsed.title) {
            return finalize(parsed, fallbackTitle: fallbackTitle, rawText: normalized)
        }

        if let parsed = parseLegacyDelimiterFormat(from: markdownParsed.title) {
            return finalize(parsed, fallbackTitle: fallbackTitle, rawText: normalized)
        }

        let fallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else {
            throw MarkExportServiceError.invalidModelResponse
        }

        let body = markdownParsed.body.isEmpty
            ? stripInvalidTitlePrefix(from: normalized, invalidTitle: markdownParsed.title)
            : markdownParsed.body

        return Parsed(title: fallback, body: body)
    }

    private static func parseMarkdownLines(from text: String) throws -> Parsed {
        let lines = text.components(separatedBy: .newlines)
        guard let titleLineIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MarkExportServiceError.invalidModelResponse
        }

        let title = normalizeTitleLine(lines[titleLineIndex])
        guard !title.isEmpty else {
            throw MarkExportServiceError.invalidModelResponse
        }

        var remainingLines = Array(lines[(titleLineIndex + 1)...])
        while let first = remainingLines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remainingLines.removeFirst()
        }

        while let first = remainingLines.first, isTagsLine(first) {
            remainingLines.removeFirst()
            while let next = remainingLines.first,
                  next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remainingLines.removeFirst()
            }
        }

        let body = remainingLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Parsed(title: title, body: body)
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

        let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = decoded.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }

        return Parsed(title: title, body: body)
    }

    private static func parseLegacyDelimiterFormat(from text: String) -> Parsed? {
        let delimiter = "-,-body-"
        guard let delimiterRange = text.range(of: delimiter) else {
            return nil
        }

        var titlePart = String(text[..<delimiterRange.lowerBound])
        let bodyPart = String(text[delimiterRange.upperBound...])

        if titlePart.hasPrefix("{-title-") {
            titlePart = String(titlePart.dropFirst("{-title-".count))
        } else if titlePart.hasPrefix("-title-") {
            titlePart = String(titlePart.dropFirst("-title-".count))
        }

        titlePart = titlePart.trimmingCharacters(in: .whitespacesAndNewlines)
        if titlePart.hasSuffix("-") {
            titlePart = String(titlePart.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let body = bodyPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titlePart.isEmpty else {
            return nil
        }

        return Parsed(title: titlePart, body: body)
    }

    private static func finalize(
        _ parsed: Parsed,
        fallbackTitle: String,
        rawText: String
    ) -> Parsed {
        guard isValidTitle(parsed.title) else {
            let fallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if fallback.isEmpty {
                return parsed
            }

            return Parsed(
                title: fallback,
                body: parsed.body.isEmpty ? rawText : parsed.body
            )
        }

        return parsed
    }

    private static func isValidTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else {
            return false
        }

        if trimmed.contains("\n") || trimmed.contains("\r") {
            return false
        }

        let lowercased = trimmed.lowercased()
        if trimmed.hasPrefix("{") {
            return false
        }

        if lowercased.contains("\"title\"") || lowercased.contains("\"body\"") {
            return false
        }

        if trimmed.contains("-,-body-") || trimmed.contains("{-title") {
            return false
        }

        return true
    }

    private static func stripInvalidTitlePrefix(from text: String, invalidTitle: String) -> String {
        var remainder = text
        if remainder.hasPrefix(invalidTitle) {
            remainder = String(remainder.dropFirst(invalidTitle.count))
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTagsLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("tags:")
    }

    private static func normalizeTitleLine(_ line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespacesAndNewlines)

        while title.hasPrefix("#") {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return title
    }

    private static func extractJSONPayload(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.hasPrefix("```") == true {
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
