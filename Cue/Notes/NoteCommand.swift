import Foundation

enum NoteCommand {
    static let keyword = "/note"

    struct Parsed: Equatable {
        let userHint: String
    }

    /// Matches `/note` or `/notes` at the start of the draft, with an optional hint after whitespace.
    static func parse(from draft: String) -> Parsed? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyword = matchedKeyword(in: trimmed) else {
            return nil
        }

        let hint = String(trimmed.dropFirst(keyword.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(userHint: hint)
    }

    /// Range of a recognized slash-command keyword at the start of the composer text.
    static func leadingKeywordRange(in text: String) -> Range<String.Index>? {
        guard let keyword = matchedKeyword(in: text) else {
            return nil
        }

        return text.startIndex..<text.index(text.startIndex, offsetBy: keyword.count)
    }

    private static func matchedKeyword(in text: String) -> String? {
        if matchesKeyword("/notes", in: text) {
            return "/notes"
        }

        if matchesKeyword("/note", in: text) {
            return "/note"
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
