import Foundation

enum ComposerCommandTextNormalizer {
    static let markKeyword = "/mark"
    private static let doubleSlashPrefix = "//"

    /// Replaces a leading `//` shortcut with `/mark`, preserving hint text after the shortcut.
    /// Bare `//` or `/mark` expands to `/mark ` so the cursor can continue with an optional hint.
    static func normalizeComposerDraft(_ text: String) -> String {
        if text == markKeyword {
            return markKeyword + " "
        }

        guard text.hasPrefix(doubleSlashPrefix) else {
            return text
        }

        let remainder = String(text.dropFirst(doubleSlashPrefix.count))
        if remainder.isEmpty {
            return markKeyword + " "
        }

        if remainder.first?.isWhitespace == true {
            return markKeyword + remainder
        }

        return markKeyword + " " + remainder
    }

    static func normalizingComposerDraftIfNeeded(_ text: String) -> (text: String, didReplace: Bool) {
        let normalized = normalizeComposerDraft(text)
        guard normalized != text else {
            return (text, false)
        }

        return (normalized, true)
    }

    /// Keeps the insertion point after the expanded `/mark` token when `//` is rewritten.
    static func adjustedSelectedRange(
        originalRange: NSRange,
        originalText: String,
        normalizedText: String
    ) -> NSRange {
        if originalText == markKeyword, normalizedText == markKeyword + " " {
            return NSRange(location: (normalizedText as NSString).length, length: 0)
        }

        guard originalText.hasPrefix(doubleSlashPrefix),
              normalizedText.hasPrefix(markKeyword) else {
            return originalRange
        }

        let lengthDelta = normalizedText.count - originalText.count
        guard lengthDelta != 0 else {
            return originalRange
        }

        let slashEndUTF16 = (doubleSlashPrefix as NSString).length
        var location = originalRange.location

        if location > slashEndUTF16 {
            location += lengthDelta
        } else if location >= slashEndUTF16 {
            location = cursorLocationAfterExpandedMarkKeyword(in: normalizedText)
        }

        return NSRange(location: location, length: originalRange.length)
    }

    private static func cursorLocationAfterExpandedMarkKeyword(in normalizedText: String) -> Int {
        let markKeywordUTF16Length = (markKeyword as NSString).length
        guard normalizedText.hasPrefix(markKeyword) else {
            return markKeywordUTF16Length
        }

        let afterKeyword = normalizedText.index(normalizedText.startIndex, offsetBy: markKeyword.count)
        if afterKeyword < normalizedText.endIndex, normalizedText[afterKeyword].isWhitespace {
            return markKeywordUTF16Length + 1
        }

        return (normalizedText as NSString).length
    }
}
