import AppKit
import Foundation

struct CaptureShortcut: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case modifierOnly
        case doubleModifier
        case keyCombo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .modifierOnly:
                "Modifier Only"
            case .doubleModifier:
                "Double Modifier"
            case .keyCombo:
                "Key Combination"
            }
        }
    }

    struct KeyOption: Identifiable, Hashable {
        let keyCode: UInt16
        let title: String

        var id: UInt16 { keyCode }
    }

    static let modifierFlagsMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    static let configurableModifierOptions: [NSEvent.ModifierFlags] = [.option, .control, .command, .shift]
    static let doubleModifierOptions: [NSEvent.ModifierFlags] = [.option, .control, .command]
    static let availableKeys: [KeyOption] = [
        .init(keyCode: 18, title: "1"),
        .init(keyCode: 19, title: "2"),
        .init(keyCode: 20, title: "3"),
        .init(keyCode: 21, title: "4"),
        .init(keyCode: 23, title: "5"),
        .init(keyCode: 22, title: "6"),
        .init(keyCode: 26, title: "7"),
        .init(keyCode: 28, title: "8"),
        .init(keyCode: 25, title: "9"),
        .init(keyCode: 29, title: "0"),
        .init(keyCode: 0, title: "A"),
        .init(keyCode: 11, title: "B"),
        .init(keyCode: 8, title: "C"),
        .init(keyCode: 2, title: "D"),
        .init(keyCode: 14, title: "E"),
        .init(keyCode: 3, title: "F"),
        .init(keyCode: 5, title: "G"),
        .init(keyCode: 4, title: "H"),
        .init(keyCode: 34, title: "I"),
        .init(keyCode: 38, title: "J"),
        .init(keyCode: 40, title: "K"),
        .init(keyCode: 37, title: "L"),
        .init(keyCode: 46, title: "M"),
        .init(keyCode: 45, title: "N"),
        .init(keyCode: 31, title: "O"),
        .init(keyCode: 35, title: "P"),
        .init(keyCode: 12, title: "Q"),
        .init(keyCode: 15, title: "R"),
        .init(keyCode: 1, title: "S"),
        .init(keyCode: 17, title: "T"),
        .init(keyCode: 32, title: "U"),
        .init(keyCode: 9, title: "V"),
        .init(keyCode: 13, title: "W"),
        .init(keyCode: 7, title: "X"),
        .init(keyCode: 16, title: "Y"),
        .init(keyCode: 6, title: "Z")
    ]
    static let defaultValue = CaptureShortcut(kind: .doubleModifier, modifierFlagsRawValue: NSEvent.ModifierFlags.option.rawValue, keyCode: nil)
    static let defaultKeyOption = availableKeys.first { $0.title == "2" } ?? availableKeys[0]

    var kind: Kind
    var modifierFlagsRawValue: UInt
    var keyCode: UInt16?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(Self.modifierFlagsMask)
    }

    var displayString: String {
        let modifierNames = orderedModifierNames(for: modifierFlags)

        switch kind {
        case .modifierOnly:
            return modifierNames.isEmpty ? "None" : modifierNames.joined(separator: " + ")
        case .doubleModifier:
            guard let modifierName = modifierNames.first else {
                return "Double Option"
            }
            return "Double \(modifierName)"
        case .keyCombo:
            let keyTitle = Self.availableKeys.first(where: { $0.keyCode == keyCode })?.title ?? "?"
            return (modifierNames + [keyTitle]).joined(separator: " + ")
        }
    }

    var normalized: CaptureShortcut {
        var normalized = self
        let filteredFlags = modifierFlags.intersection(Self.modifierFlagsMask)
        normalized.modifierFlagsRawValue = filteredFlags.rawValue

        if filteredFlags.isEmpty {
            normalized.modifierFlagsRawValue = NSEvent.ModifierFlags([.shift, .option]).rawValue
        }

        switch normalized.kind {
        case .modifierOnly:
            normalized.keyCode = nil
        case .doubleModifier:
            let supportedFlags = filteredFlags.intersection(NSEvent.ModifierFlags(Self.doubleModifierOptions))
            let normalizedFlag = Self.doubleModifierOptions.first(where: { supportedFlags.contains($0) }) ?? .option
            normalized.modifierFlagsRawValue = normalizedFlag.rawValue
            normalized.keyCode = nil
        case .keyCombo:
            if normalized.keyCode == nil {
                normalized.keyCode = Self.defaultKeyOption.keyCode
            }
        }

        return normalized
    }

    mutating func setModifier(_ modifier: NSEvent.ModifierFlags, enabled: Bool) {
        var updated = modifierFlags
        if enabled {
            updated.insert(modifier)
        } else {
            updated.remove(modifier)
        }
        modifierFlagsRawValue = updated.rawValue
    }

    func contains(_ modifier: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(modifier)
    }

    private func orderedModifierNames(for flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.control) { names.append("Control") }
        if flags.contains(.option) { names.append("Option") }
        if flags.contains(.shift) { names.append("Shift") }
        if flags.contains(.command) { names.append("Command") }
        return names
    }
}

enum ShortcutFeatureCopy {
    static let openChatName = "Open Chat"
    static let openChatBinding = "Double Shift"
    static let openChatSummary = "Opens the chat UI. If text is selected, Cue attaches it before opening the composer."

    static let addToContextName = "Add To Context"
    static let addToContextSummary = "Double Option by default. Adds selected text to the context window when available, otherwise starts screenshot capture."
}

@MainActor
final class HotkeyManager {
    private enum DoubleShiftConfig {
        static let maxTapDuration: CFTimeInterval = 0.25
        static let maxIntervalBetweenTaps: CFTimeInterval = 0.35
    }

    private let permissionManager = PermissionManager()
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var onTrigger: (() -> Void)?
    private var onConversationTrigger: (() -> Void)?
    private var onDismissOverlayTrigger: (() -> Void)?
    private var shortcut = CaptureShortcut.defaultValue
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var isMonitoring = false
    private var bareShiftKeyDownAt: CFTimeInterval?
    private var lastBareShiftTapAt: CFTimeInterval?
    private var bareCaptureModifierKeyDownAt: CFTimeInterval?
    private var lastBareCaptureModifierTapAt: CFTimeInterval?

    func startMonitoring(
        shortcut: CaptureShortcut,
        onTrigger: @escaping () -> Void,
        onConversationTrigger: @escaping () -> Void,
        onDismissOverlayTrigger: @escaping () -> Void
    ) {
        self.shortcut = shortcut.normalized
        self.onTrigger = onTrigger
        self.onConversationTrigger = onConversationTrigger
        self.onDismissOverlayTrigger = onDismissOverlayTrigger

        guard !isMonitoring else { return }
        isMonitoring = true
        installMonitors()
    }

    func update(shortcut: CaptureShortcut) {
        self.shortcut = shortcut.normalized
    }

    private func installMonitors() {
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event)
            return event
        }

        guard permissionManager.ensureAccessibilityPermission(promptIfNeeded: true) else {
            return
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyDown(event)
        }
    }

    private func removeMonitors() {
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        handleDoubleShift(event)
        handleDoubleModifierShortcut(event)

        let currentFlags = filteredModifierFlags(from: event.modifierFlags)
        defer { lastModifierFlags = currentFlags }

        guard shortcut.kind == .modifierOnly else { return }
        guard currentFlags == shortcut.modifierFlags else { return }
        guard lastModifierFlags != shortcut.modifierFlags else { return }

        onTrigger?()
    }

    private func handleLocalKeyDown(_ event: NSEvent) {
        guard shortcut.kind == .keyCombo else { return }
        guard !event.isARepeat else { return }
        guard event.keyCode == shortcut.keyCode else { return }
        guard filteredModifierFlags(from: event.modifierFlags) == shortcut.modifierFlags else { return }

        onTrigger?()
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        if event.keyCode == 53, filteredModifierFlags(from: event.modifierFlags).isEmpty {
            onDismissOverlayTrigger?()
            return
        }

        guard shortcut.kind == .keyCombo else { return }
        guard !event.isARepeat else { return }
        guard event.keyCode == shortcut.keyCode else { return }
        guard filteredModifierFlags(from: event.modifierFlags) == shortcut.modifierFlags else { return }

        onTrigger?()
    }

    private func filteredModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(CaptureShortcut.modifierFlagsMask)
    }

    private func handleDoubleModifierShortcut(_ event: NSEvent) {
        guard shortcut.kind == .doubleModifier else { return }

        let currentFlags = filteredModifierFlags(from: event.modifierFlags)
        let targetModifier = shortcut.modifierFlags
        let now = CFAbsoluteTimeGetCurrent()

        if currentFlags == targetModifier, !lastModifierFlags.contains(targetModifier) {
            bareCaptureModifierKeyDownAt = now
            return
        }

        if currentFlags.isEmpty, lastModifierFlags == targetModifier {
            defer { bareCaptureModifierKeyDownAt = nil }

            guard let bareCaptureModifierKeyDownAt,
                  now - bareCaptureModifierKeyDownAt <= DoubleShiftConfig.maxTapDuration else {
                return
            }

            if let lastBareCaptureModifierTapAt,
               now - lastBareCaptureModifierTapAt <= DoubleShiftConfig.maxIntervalBetweenTaps {
                self.lastBareCaptureModifierTapAt = nil
                onTrigger?()
            } else {
                lastBareCaptureModifierTapAt = now
            }
        }
    }

    private func handleDoubleShift(_ event: NSEvent) {
        let currentFlags = filteredModifierFlags(from: event.modifierFlags)
        let now = CFAbsoluteTimeGetCurrent()

        if currentFlags == [.shift], !lastModifierFlags.contains(.shift) {
            bareShiftKeyDownAt = now
            return
        }

        if currentFlags.isEmpty, lastModifierFlags == [.shift] {
            defer { bareShiftKeyDownAt = nil }

            guard let bareShiftKeyDownAt,
                  now - bareShiftKeyDownAt <= DoubleShiftConfig.maxTapDuration else {
                return
            }

            if let lastBareShiftTapAt,
               now - lastBareShiftTapAt <= DoubleShiftConfig.maxIntervalBetweenTaps {
                self.lastBareShiftTapAt = nil
                onConversationTrigger?()
            } else {
                lastBareShiftTapAt = now
            }
        }
    }
}