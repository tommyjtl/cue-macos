import Foundation

enum MarkCommand {
    static let keywords = ["//", "/mark"]

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

    static func hasMarkableContent(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        screenshotCount: Int,
        selectedTextContextCount: Int
    ) -> Bool {
        MarkExportModeResolver.resolve(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages,
            screenshotCount: screenshotCount,
            selectedTextContextCount: selectedTextContextCount
        ) != nil
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
