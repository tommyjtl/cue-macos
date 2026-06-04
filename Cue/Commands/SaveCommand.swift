import Foundation

enum SaveCommand {
    static let keywords = ["/save", "/notes", "/note"]

    struct Parsed: Equatable {
        let matchedKeyword: String
        let userHint: String
    }

    static func parse(from draft: String) -> Parsed? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyword = matchedKeyword(in: trimmed) else {
            return nil
        }

        let hint = String(trimmed.dropFirst(keyword.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(matchedKeyword: keyword, userHint: hint)
    }

    static func hasExportableContent(
        sessionMessages: [ConversationMessageDTO],
        screenshotCount: Int,
        selectedTextContextCount: Int,
        browserPageContextCount: Int
    ) -> Bool {
        if !sessionMessages.isEmpty {
            return true
        }

        return screenshotCount > 0
            || selectedTextContextCount > 0
            || browserPageContextCount > 0
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

/// Legacy name for save command parsing.
enum NoteCommand {
    static func parse(from draft: String) -> SaveCommand.Parsed? {
        SaveCommand.parse(from: draft)
    }

    static func hasExportableContent(
        sessionMessages: [ConversationMessageDTO],
        screenshotCount: Int,
        selectedTextContextCount: Int,
        browserPageContextCount: Int
    ) -> Bool {
        SaveCommand.hasExportableContent(
            sessionMessages: sessionMessages,
            screenshotCount: screenshotCount,
            selectedTextContextCount: selectedTextContextCount,
            browserPageContextCount: browserPageContextCount
        )
    }

    static func leadingKeywordRange(in text: String) -> Range<String.Index>? {
        SaveCommand.leadingKeywordRange(in: text)
    }
}
