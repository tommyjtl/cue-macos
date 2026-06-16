import Foundation

enum SearchCommand {
    static let keywords = ["/search"]

    struct Parsed: Equatable {
        let matchedKeyword: String
        let query: String
    }

    static func parse(from draft: String) -> Parsed? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyword = matchedKeyword(in: trimmed) else {
            return nil
        }

        let query = String(trimmed.dropFirst(keyword.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(matchedKeyword: keyword, query: query)
    }

    static func leadingKeywordRange(in text: String) -> Range<String.Index>? {
        guard let keyword = matchedKeyword(in: text) else {
            return nil
        }

        return text.startIndex..<text.index(text.startIndex, offsetBy: keyword.count)
    }

    private static func matchedKeyword(in text: String) -> String? {
        for keyword in keywords {
            if matchesKeyword(keyword, in: text) {
                return keyword
            }
        }

        return nil
    }

    private static func matchesKeyword(_ keyword: String, in text: String) -> Bool {
        guard text.hasPrefix(keyword) else {
            return false
        }

        if text.count == keyword.count {
            return true
        }

        let nextIndex = text.index(text.startIndex, offsetBy: keyword.count)
        return text[nextIndex].isWhitespace
    }
}
