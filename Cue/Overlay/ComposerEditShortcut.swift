import AppKit

enum ComposerEditShortcut {
    private static let modifierFlagsMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    static func selector(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection(modifierFlagsMask)

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            guard flags == [.command] else { return nil }
            return #selector(NSText.selectAll(_:))
        case "c":
            guard flags == [.command] else { return nil }
            return #selector(NSText.copy(_:))
        case "v":
            guard flags == [.command] else { return nil }
            return #selector(NSText.paste(_:))
        case "x":
            guard flags == [.command] else { return nil }
            return #selector(NSText.cut(_:))
        case "z":
            switch flags {
            case [.command, .shift]:
                return Selector(("redo:"))
            case [.command]:
                return Selector(("undo:"))
            default:
                return nil
            }
        default:
            return nil
        }
    }

    static func perform(with event: NSEvent, sender: Any?) -> Bool {
        guard let selector = selector(for: event) else { return false }
        return NSApp.sendAction(selector, to: nil, from: sender)
    }
}
