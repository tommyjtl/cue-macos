import Foundation

struct SearchResultSource: Codable, Equatable, Sendable {
    let filePath: String
    let title: String
    let excerpt: String
    let section: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case title
        case excerpt
        case section
    }
}

enum SearchResultMessage {
    nonisolated static let sourcesBeginMarker = "<!-- cue-search-sources"
    nonisolated static let sourcesEndMarker = "-->"

    static func messageText(answer: String, sources: [SearchResultSource]) -> String {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sources.isEmpty else {
            return trimmedAnswer
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sources),
              let json = String(data: data, encoding: .utf8) else {
            return trimmedAnswer
        }

        return """
        \(trimmedAnswer)

        \(sourcesBeginMarker)
        \(json)
        \(sourcesEndMarker)
        """
    }

    static func parse(from messageText: String) -> (answer: String, sources: [SearchResultSource])? {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let beginRange = trimmed.range(of: sourcesBeginMarker) else {
            return nil
        }

        let afterBegin = trimmed[beginRange.upperBound...]
        guard let endRange = afterBegin.range(of: sourcesEndMarker) else {
            return nil
        }

        let json = afterBegin[..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let sources = try? JSONDecoder().decode([SearchResultSource].self, from: data) else {
            return nil
        }

        let answer = trimmed[..<beginRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (answer, sources)
    }
}
