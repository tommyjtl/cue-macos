import AppKit
import Foundation

enum ShortcutRecorderSupport {
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]
    static let doubleTapMaxDuration: TimeInterval = 0.25
    static let doubleTapMaxInterval: TimeInterval = 0.35

    static func filteredModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(CaptureShortcut.modifierFlagsMask)
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    static func modifierTitle(for flags: NSEvent.ModifierFlags) -> String {
        switch flags {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        default:
            return "Modifier"
        }
    }

    static func orderedModifierTitles(for flags: NSEvent.ModifierFlags) -> [String] {
        var titles: [String] = []
        if flags.contains(.control) { titles.append("Control") }
        if flags.contains(.option) { titles.append("Option") }
        if flags.contains(.shift) { titles.append("Shift") }
        if flags.contains(.command) { titles.append("Command") }
        return titles
    }

    static func keyTitle(for keyCode: UInt16) -> String {
        DismissChatShortcut.keyTitle(for: keyCode)
    }
}

extension CaptureShortcut {
    var displayTokens: [String] {
        switch kind {
        case .modifierOnly:
            return ShortcutRecorderSupport.orderedModifierTitles(for: modifierFlags)
        case .doubleModifier:
            guard let modifier = ShortcutRecorderSupport.orderedModifierTitles(for: modifierFlags).first else {
                return ["Double Modifier"]
            }
            return ["Double", modifier]
        case .keyCombo:
            let keyTitle = keyCode.map { ShortcutRecorderSupport.keyTitle(for: $0) } ?? "Key"
            return ShortcutRecorderSupport.orderedModifierTitles(for: modifierFlags) + [keyTitle]
        }
    }
}

extension DismissChatShortcut {
    var displayTokens: [String] {
        Array(repeating: Self.keyTitle(for: keyCode), count: pressCount)
    }
}

@MainActor
final class CaptureShortcutRecordingSession {
    private let doubleModifierOptions: [NSEvent.ModifierFlags]
    private let normalize: (CaptureShortcut) -> CaptureShortcut

    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var bareModifierKeyDownAt: TimeInterval?
    private var lastBareModifierTapAt: TimeInterval?
    private var pendingModifierOnly: NSEvent.ModifierFlags?

    var previewTokens: [String] = []
    var previewHint = "Press the shortcut you want to use."

    init(
        doubleModifierOptions: [NSEvent.ModifierFlags]? = nil,
        normalize: ((CaptureShortcut) -> CaptureShortcut)? = nil
    ) {
        self.doubleModifierOptions = doubleModifierOptions ?? CaptureShortcut.doubleModifierOptions
        self.normalize = normalize ?? { $0.normalized }
    }

    func reset() {
        lastModifierFlags = []
        bareModifierKeyDownAt = nil
        lastBareModifierTapAt = nil
        pendingModifierOnly = nil
        previewTokens = []
        previewHint = "Press the shortcut you want to use."
    }

    func handle(_ event: NSEvent) -> CaptureShortcut? {
        switch event.type {
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            return handleFlagsChanged(event)
        default:
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> CaptureShortcut? {
        guard !event.isARepeat else { return nil }

        if event.keyCode == 53 {
            return nil
        }

        let modifiers = ShortcutRecorderSupport.filteredModifierFlags(from: event.modifierFlags)

        if ShortcutRecorderSupport.isModifierKeyCode(event.keyCode),
           modifiers.isEmpty || modifiers == modifierFlags(for: event.keyCode) {
            let modifier = modifierFlags(for: event.keyCode)
            pendingModifierOnly = modifier
            previewTokens = [ShortcutRecorderSupport.modifierTitle(for: modifier)]
            previewHint = "Tap the same modifier again for Double, or click Done for Modifier Only."
            return nil
        }

        pendingModifierOnly = nil

        var shortcut = CaptureShortcut(
            kind: .keyCombo,
            modifierFlagsRawValue: modifiers.rawValue,
            keyCode: event.keyCode
        )
        shortcut = normalize(shortcut)
        previewTokens = shortcut.displayTokens
        previewHint = "Shortcut recorded."
        return shortcut
    }

    private func handleFlagsChanged(_ event: NSEvent) -> CaptureShortcut? {
        let currentFlags = ShortcutRecorderSupport.filteredModifierFlags(from: event.modifierFlags)
        defer { lastModifierFlags = currentFlags }

        guard let bareModifier = singleModifier(in: currentFlags) ?? singleModifier(in: lastModifierFlags) else {
            if !currentFlags.isEmpty {
                previewTokens = ShortcutRecorderSupport.orderedModifierTitles(for: currentFlags)
                previewHint = "Press a key to complete the combination."
            }
            return nil
        }

        let now = event.timestamp

        if currentFlags == bareModifier, !lastModifierFlags.contains(bareModifier) {
            bareModifierKeyDownAt = now
            previewTokens = [ShortcutRecorderSupport.modifierTitle(for: bareModifier)]
            previewHint = "Release, then tap the same modifier again."
            return nil
        }

        if currentFlags.isEmpty, lastModifierFlags == bareModifier {
            defer { bareModifierKeyDownAt = nil }

            guard let bareModifierKeyDownAt,
                  now - bareModifierKeyDownAt <= ShortcutRecorderSupport.doubleTapMaxDuration else {
                return nil
            }

            if let lastBareModifierTapAt,
               now - lastBareModifierTapAt <= ShortcutRecorderSupport.doubleTapMaxInterval {
                self.lastBareModifierTapAt = nil
                pendingModifierOnly = nil

                var shortcut = CaptureShortcut(
                    kind: .doubleModifier,
                    modifierFlagsRawValue: bareModifier.rawValue,
                    keyCode: nil
                )
                shortcut = normalize(shortcut)
                previewTokens = shortcut.displayTokens
                previewHint = "Shortcut recorded."
                return shortcut
            }

            lastBareModifierTapAt = now
            previewTokens = [ShortcutRecorderSupport.modifierTitle(for: bareModifier)]
            previewHint = "Tap the same modifier again."
        }

        return nil
    }

    func consumePendingModifierOnlyIfReady() -> CaptureShortcut? {
        guard let pendingModifierOnly else { return nil }

        var shortcut = CaptureShortcut(
            kind: .modifierOnly,
            modifierFlagsRawValue: pendingModifierOnly.rawValue,
            keyCode: nil
        )
        shortcut = normalize(shortcut)
        previewTokens = shortcut.displayTokens
        previewHint = "Shortcut recorded."
        self.pendingModifierOnly = nil
        return shortcut
    }

    private func singleModifier(in flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags? {
        for modifier in doubleModifierOptions where flags == modifier {
            return modifier
        }
        return nil
    }

    private func modifierFlags(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        default:
            return []
        }
    }
}

@MainActor
final class DismissChatShortcutRecordingSession {
    private var presses: [UInt16] = []
    private var lastPressAt: TimeInterval?

    var previewTokens: [String] = []
    var previewHint = "Press the same key twice to finish."

    func reset() {
        presses = []
        lastPressAt = nil
        previewTokens = []
        previewHint = "Press the same key twice to finish."
    }

    func handle(_ event: NSEvent) -> DismissChatShortcut? {
        guard event.type == .keyDown else { return nil }
        guard !event.isARepeat else { return nil }
        guard ShortcutRecorderSupport.filteredModifierFlags(from: event.modifierFlags).isEmpty else { return nil }

        let now = event.timestamp
        if let lastPressAt, now - lastPressAt > DismissChatShortcut.defaultMaxIntervalBetweenPresses {
            presses = []
        }

        if let lastKey = presses.last, lastKey != event.keyCode, presses.count == 1 {
            presses = []
        } else if let lastKey = presses.last, lastKey != event.keyCode {
            presses = []
        }

        presses.append(event.keyCode)
        lastPressAt = now

        previewTokens = presses.map { ShortcutRecorderSupport.keyTitle(for: $0) }
        previewHint = presses.count == 1
            ? "Press \(ShortcutRecorderSupport.keyTitle(for: event.keyCode)) one more time."
            : "Shortcut recorded."

        guard presses.count >= DismissChatShortcut.minimumPressCount else {
            return nil
        }

        let shortcut = DismissChatShortcut(
            kind: .repeatedKey,
            keyCode: event.keyCode,
            pressCount: presses.count,
            maxIntervalBetweenPresses: DismissChatShortcut.defaultMaxIntervalBetweenPresses,
            modifierFlagsRawValue: 0
        ).normalized

        previewHint = "Shortcut recorded."
        return shortcut
    }
}
