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
    static let defaultOpenChatValue = CaptureShortcut(kind: .doubleModifier, modifierFlagsRawValue: NSEvent.ModifierFlags.shift.rawValue, keyCode: nil)
    static let defaultKeyOption = availableKeys.first { $0.title == "2" } ?? availableKeys[0]
    static let doubleModifierOptionsWithShift: [NSEvent.ModifierFlags] = [.shift, .option, .control, .command]

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

    func normalizedOpenChat() -> CaptureShortcut {
        var normalized = self
        let filteredFlags = modifierFlags.intersection(Self.modifierFlagsMask)
        normalized.modifierFlagsRawValue = filteredFlags.rawValue

        switch normalized.kind {
        case .modifierOnly:
            normalized.keyCode = nil
            if filteredFlags.isEmpty {
                normalized.modifierFlagsRawValue = NSEvent.ModifierFlags.shift.rawValue
            }
        case .doubleModifier:
            let supportedFlags = filteredFlags.intersection(NSEvent.ModifierFlags(Self.doubleModifierOptionsWithShift))
            let normalizedFlag = Self.doubleModifierOptionsWithShift.first(where: { supportedFlags.contains($0) }) ?? .shift
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

struct DismissChatShortcut: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case repeatedKey

        var id: String { rawValue }

        var title: String {
            "Repeated Key"
        }
    }

    static let escapeKeyCode: UInt16 = 53
    static let defaultMaxIntervalBetweenPresses: TimeInterval = 0.35
    static let duplicateEventTolerance: TimeInterval = 0.05
    static let defaultValue = DismissChatShortcut(
        kind: .repeatedKey,
        keyCode: escapeKeyCode,
        pressCount: 2,
        maxIntervalBetweenPresses: defaultMaxIntervalBetweenPresses,
        modifierFlagsRawValue: 0
    )
    static let minimumPressCount = 2

    static let availableKeys: [CaptureShortcut.KeyOption] = {
        [CaptureShortcut.KeyOption(keyCode: escapeKeyCode, title: "Escape")] + CaptureShortcut.availableKeys
    }()

    var kind: Kind
    var keyCode: UInt16
    var pressCount: Int
    var maxIntervalBetweenPresses: TimeInterval
    var modifierFlagsRawValue: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(CaptureShortcut.modifierFlagsMask)
    }

    var normalized: DismissChatShortcut {
        var normalized = self
        normalized.pressCount = min(max(pressCount, 2), 5)
        normalized.maxIntervalBetweenPresses = min(max(maxIntervalBetweenPresses, 0.15), 1.0)
        normalized.modifierFlagsRawValue = modifierFlags.rawValue
        if normalized.keyCode == 0 {
            normalized.keyCode = Self.escapeKeyCode
        }
        return normalized
    }

    var displayString: String {
        let keyTitle = Self.keyTitle(for: keyCode)
        switch pressCount {
        case 2:
            return "Double \(keyTitle)"
        case 3:
            return "Triple \(keyTitle)"
        default:
            return "\(pressCount)× \(keyTitle)"
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        guard kind == .repeatedKey else { return false }
        guard event.keyCode == keyCode else { return false }

        let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return event.modifierFlags.intersection(modifierMask) == modifierFlags
    }

    static func keyTitle(for keyCode: UInt16) -> String {
        if keyCode == escapeKeyCode {
            return "Escape"
        }

        return CaptureShortcut.availableKeys.first(where: { $0.keyCode == keyCode })?.title ?? "Key \(keyCode)"
    }
}

struct RepeatedKeyPressTracker {
    private(set) var pressCount = 0
    private var lastPressAt: TimeInterval?
    private var lastHandledEventTimestamp: TimeInterval?

    mutating func reset() {
        pressCount = 0
        lastPressAt = nil
        lastHandledEventTimestamp = nil
    }

    mutating func registerPress(
        shortcut: DismissChatShortcut,
        now: TimeInterval = CFAbsoluteTimeGetCurrent()
    ) -> Bool {

        if let lastHandledEventTimestamp,
           now - lastHandledEventTimestamp < DismissChatShortcut.duplicateEventTolerance {
            return false
        }
        lastHandledEventTimestamp = now

        if let lastPressAt,
           now - lastPressAt > shortcut.maxIntervalBetweenPresses {
            pressCount = 0
        }

        pressCount += 1
        lastPressAt = now

        guard pressCount >= shortcut.pressCount else {
            return false
        }

        reset()
        return true
    }
}

enum ShortcutFeatureCopy {
    static let openChatName = "Open Chat"
    static let openChatBinding = "Double Shift"
    static let openChatSummary = "Opens chat near the cursor. Resumes the active overlay conversation when one is in progress, otherwise starts fresh."

    static let addToContextName = "Add To Context"
    static let addToContextSummary = "Double Option by default. Starts a screenshot region capture and attaches it to the context window."

    static let dismissChatName = "Dismiss Chat"
    static let dismissChatSummary = "Closes the chat composer while keeping the overlay available. Default is Double Escape."
}

@MainActor
final class HotkeyManager {
    private enum DoubleShiftConfig {
        static let maxTapDuration: CFTimeInterval = 0.25
        static let maxIntervalBetweenTaps: CFTimeInterval = 0.35
    }

    private let permissionManager = PermissionManager.shared
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var onTrigger: (() -> Void)?
    private var onConversationTrigger: (() -> Void)?
    private var captureShortcut = CaptureShortcut.defaultValue
    private var openChatShortcut = CaptureShortcut.defaultOpenChatValue
    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var isMonitoring = false
    private var captureDoubleTapState = DoubleModifierTapState()
    private var openChatDoubleTapState = DoubleModifierTapState()
    private var isShortcutHandlingPaused = false

    private struct DoubleModifierTapState {
        var bareModifierKeyDownAt: CFTimeInterval?
        var lastBareModifierTapAt: CFTimeInterval?
    }

    func startMonitoring(
        captureShortcut: CaptureShortcut,
        openChatShortcut: CaptureShortcut,
        onTrigger: @escaping () -> Void,
        onConversationTrigger: @escaping () -> Void
    ) {
        self.captureShortcut = captureShortcut.normalized
        self.openChatShortcut = openChatShortcut.normalizedOpenChat()
        self.onTrigger = onTrigger
        self.onConversationTrigger = onConversationTrigger

        guard !isMonitoring else { return }
        isMonitoring = true
        installMonitors()
    }

    func updateCaptureShortcut(_ shortcut: CaptureShortcut) {
        captureShortcut = shortcut.normalized
    }

    func updateOpenChatShortcut(_ shortcut: CaptureShortcut) {
        openChatShortcut = shortcut.normalizedOpenChat()
    }

    func setShortcutHandlingPaused(_ paused: Bool) {
        isShortcutHandlingPaused = paused
    }

    /// Global monitors require Accessibility. Call when permission is granted after launch.
    func refreshAccessibilityDependentMonitors() {
        if permissionManager.hasAccessibilityPermission() {
            installGlobalMonitorsIfNeeded()
        } else if globalFlagsMonitor != nil || globalKeyDownMonitor != nil {
            removeGlobalMonitors()
            print("[HotkeyManager] Accessibility not granted — global shortcuts (double Shift/Option) inactive")
        }
    }

    private func installMonitors() {
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event)
            return event
        }

        installGlobalMonitorsIfNeeded()
    }

    private func installGlobalMonitorsIfNeeded() {
        guard permissionManager.hasAccessibilityPermission() else {
            print("[HotkeyManager] Skipping global monitors — Accessibility not granted yet")
            return
        }

        if globalFlagsMonitor != nil, globalKeyDownMonitor != nil {
            return
        }

        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        }

        if globalKeyDownMonitor == nil {
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleGlobalKeyDown(event)
            }
        }

        if globalFlagsMonitor != nil {
            print("[HotkeyManager] Global shortcut monitors active")
        } else {
            print("[HotkeyManager] Failed to install global monitors — check Accessibility permission")
        }
    }

    private func removeGlobalMonitors() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
    }

    private func removeMonitors() {
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
        removeGlobalMonitors()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard !isShortcutHandlingPaused else { return }

        let currentFlags = filteredModifierFlags(from: event.modifierFlags)
        defer { lastModifierFlags = currentFlags }

        handleDoubleModifierShortcut(
            event,
            shortcut: openChatShortcut,
            state: &openChatDoubleTapState,
            onTrigger: onConversationTrigger
        )
        handleDoubleModifierShortcut(
            event,
            shortcut: captureShortcut,
            state: &captureDoubleTapState,
            onTrigger: onTrigger
        )

        handleModifierOnlyShortcut(
            currentFlags: currentFlags,
            shortcut: openChatShortcut,
            onTrigger: onConversationTrigger
        )
        handleModifierOnlyShortcut(
            currentFlags: currentFlags,
            shortcut: captureShortcut,
            onTrigger: onTrigger
        )
    }

    private func handleModifierOnlyShortcut(
        currentFlags: NSEvent.ModifierFlags,
        shortcut: CaptureShortcut,
        onTrigger: (() -> Void)?
    ) {
        guard shortcut.kind == .modifierOnly else { return }
        guard currentFlags == shortcut.modifierFlags else { return }
        guard lastModifierFlags != shortcut.modifierFlags else { return }

        onTrigger?()
    }

    private func handleLocalKeyDown(_ event: NSEvent) {
        guard !isShortcutHandlingPaused else { return }

        handleKeyComboShortcut(event, shortcut: openChatShortcut, onTrigger: onConversationTrigger)
        handleKeyComboShortcut(event, shortcut: captureShortcut, onTrigger: onTrigger)
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard !isShortcutHandlingPaused else { return }

        handleKeyComboShortcut(event, shortcut: openChatShortcut, onTrigger: onConversationTrigger)
        handleKeyComboShortcut(event, shortcut: captureShortcut, onTrigger: onTrigger)
    }

    private func handleKeyComboShortcut(
        _ event: NSEvent,
        shortcut: CaptureShortcut,
        onTrigger: (() -> Void)?
    ) {
        guard shortcut.kind == .keyCombo else { return }
        guard !event.isARepeat else { return }
        guard event.keyCode == shortcut.keyCode else { return }
        guard filteredModifierFlags(from: event.modifierFlags) == shortcut.modifierFlags else { return }

        onTrigger?()
    }

    private func filteredModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(CaptureShortcut.modifierFlagsMask)
    }

    private func handleDoubleModifierShortcut(
        _ event: NSEvent,
        shortcut: CaptureShortcut,
        state: inout DoubleModifierTapState,
        onTrigger: (() -> Void)?
    ) {
        guard shortcut.kind == .doubleModifier else { return }

        let currentFlags = filteredModifierFlags(from: event.modifierFlags)
        let targetModifier = shortcut.modifierFlags
        let now = CFAbsoluteTimeGetCurrent()

        if currentFlags == targetModifier, !lastModifierFlags.contains(targetModifier) {
            state.bareModifierKeyDownAt = now
            return
        }

        if currentFlags.isEmpty, lastModifierFlags == targetModifier {
            defer { state.bareModifierKeyDownAt = nil }

            guard let bareModifierKeyDownAt = state.bareModifierKeyDownAt,
                  now - bareModifierKeyDownAt <= DoubleShiftConfig.maxTapDuration else {
                return
            }

            if let lastBareModifierTapAt = state.lastBareModifierTapAt,
               now - lastBareModifierTapAt <= DoubleShiftConfig.maxIntervalBetweenTaps {
                state.lastBareModifierTapAt = nil
                onTrigger?()
            } else {
                state.lastBareModifierTapAt = now
            }
        }
    }
}