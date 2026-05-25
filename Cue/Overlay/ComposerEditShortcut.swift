import AppKit

enum ComposerEditShortcut {
    static func selector(for event: NSEvent) -> Selector? {
        guard event.modifierFlags.contains(.command) else { return nil }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            return #selector(NSText.selectAll(_:))
        case "c":
            return #selector(NSText.copy(_:))
        case "v":
            return #selector(NSText.paste(_:))
        case "x":
            return #selector(NSText.cut(_:))
        case "z":
            return event.modifierFlags.contains(.shift)
                ? Selector(("redo:"))
                : Selector(("undo:"))
        default:
            return nil
        }
    }

    static func perform(with event: NSEvent, sender: Any?) -> Bool {
        guard let selector = selector(for: event) else { return false }
        return NSApp.sendAction(selector, to: nil, from: sender)
    }
}
