import AppKit

enum ComposerSlashCommandHighlighter {
    static let keywordColor = NSColor.systemPurple

    static func apply(to textView: NSTextView, text: String, font: NSFont) {
        let selectedRange = textView.selectedRange()
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )

        if let keywordRange = ComposerCommandRegistry.leadingKeywordRange(in: text) {
            let nsRange = NSRange(keywordRange, in: text)
            attributed.addAttribute(.foregroundColor, value: keywordColor, range: nsRange)
        }

        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(selectedRange)
    }
}
