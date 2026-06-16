import Foundation

enum ParsedComposerCommand: Equatable {
    case save(SaveCommand.Parsed)
    case mark(MarkCommand.Parsed)
    case search(SearchCommand.Parsed)
}

enum ComposerCommandRegistry {
    static func parse(from draft: String) -> ParsedComposerCommand? {
        if let mark = MarkCommand.parse(from: draft) {
            return .mark(mark)
        }

        if let search = SearchCommand.parse(from: draft) {
            return .search(search)
        }

        if let save = SaveCommand.parse(from: draft) {
            return .save(save)
        }

        return nil
    }

    static func leadingKeywordRange(in text: String) -> Range<String.Index>? {
        MarkCommand.leadingKeywordRange(in: text)
            ?? SearchCommand.leadingKeywordRange(in: text)
            ?? SaveCommand.leadingKeywordRange(in: text)
    }
}
