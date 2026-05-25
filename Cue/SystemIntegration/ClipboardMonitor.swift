import AppKit
import Foundation

/// Attaches clipboard text to context when the user presses ⌘C twice in quick succession.
@MainActor
final class ClipboardMonitor {
    typealias Handler = @MainActor (_ text: String, _ sourceApp: NSRunningApplication?) -> Void

    private enum DoubleCopyConfig {
        static let copyKeyCode: UInt16 = 8
        static let maxIntervalBetweenCopies: CFTimeInterval = 0.5
    }

    private let permissionManager = PermissionManager.shared
    private var globalCopyMonitor: Any?
    private var localCopyMonitor: Any?
    private var lastCopyKeyDownAt: CFTimeInterval?
    private var onAttachFromClipboard: Handler?

    nonisolated(unsafe) private static var ignoreCopyShortcutUntil: Date?

    func start(onAttachFromClipboard: @escaping Handler) {
        guard self.onAttachFromClipboard == nil else { return }

        self.onAttachFromClipboard = onAttachFromClipboard
        installCopyMonitors()
        print("[ClipboardMonitor] Started — attach on double ⌘C")
    }

    func stop() {
        removeCopyMonitors()
        onAttachFromClipboard = nil
        lastCopyKeyDownAt = nil
    }

    func refreshAccessibilityDependentMonitors() {
        if permissionManager.hasAccessibilityPermission() {
            installGlobalCopyMonitorIfNeeded()
        } else {
            removeGlobalCopyMonitor()
            print("[ClipboardMonitor] Accessibility not granted — double ⌘C works only while Cue is focused")
        }
    }

    nonisolated static func temporarilyIgnoreCopyShortcut(for interval: TimeInterval = 0.35) {
        ignoreCopyShortcutUntil = Date().addingTimeInterval(interval)
    }

    nonisolated static func readString(from pasteboard: NSPasteboard) -> String? {
        guard pasteboard.availableType(from: [.string]) == .string else {
            return nil
        }

        guard let value = pasteboard.string(forType: .string) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func describe(_ text: String?) -> String {
        guard let text else { return "nil" }
        return "\"\(preview(text))\" (\(text.count) chars)"
    }

    nonisolated static func preview(_ text: String, limit: Int = 80) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    nonisolated static func shouldAttachAfterCopyKeyPress(
        lastCopyKeyDownAt: CFTimeInterval?,
        now: CFTimeInterval,
        maxIntervalBetweenCopies: CFTimeInterval = DoubleCopyConfig.maxIntervalBetweenCopies
    ) -> (nextLastCopyKeyDownAt: CFTimeInterval?, shouldAttach: Bool) {
        if let lastCopyKeyDownAt,
           now - lastCopyKeyDownAt <= maxIntervalBetweenCopies {
            return (nil, true)
        }

        return (now, false)
    }

    private func installCopyMonitors() {
        if localCopyMonitor == nil {
            localCopyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleCopyKeyDown(event)
                return event
            }
        }

        installGlobalCopyMonitorIfNeeded()
    }

    private func installGlobalCopyMonitorIfNeeded() {
        guard permissionManager.hasAccessibilityPermission() else { return }
        guard globalCopyMonitor == nil else { return }

        globalCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCopyKeyDown(event)
        }

        if globalCopyMonitor != nil {
            print("[ClipboardMonitor] Global double-⌘C monitor active")
        }
    }

    private func removeGlobalCopyMonitor() {
        if let globalCopyMonitor {
            NSEvent.removeMonitor(globalCopyMonitor)
            self.globalCopyMonitor = nil
        }
    }

    private func removeCopyMonitors() {
        if let localCopyMonitor {
            NSEvent.removeMonitor(localCopyMonitor)
            self.localCopyMonitor = nil
        }
        removeGlobalCopyMonitor()
    }

    private func handleCopyKeyDown(_ event: NSEvent) {
        guard !Self.shouldIgnoreCopyShortcut() else { return }
        guard event.keyCode == DoubleCopyConfig.copyKeyCode else { return }
        guard event.modifierFlags.contains(.command) else { return }
        guard !event.modifierFlags.contains(.option) else { return }
        guard !event.isARepeat else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let decision = Self.shouldAttachAfterCopyKeyPress(lastCopyKeyDownAt: lastCopyKeyDownAt, now: now)
        lastCopyKeyDownAt = decision.nextLastCopyKeyDownAt

        if decision.shouldAttach {
            attachMostRecentClipboardText()
        } else {
            print("[ClipboardMonitor] First ⌘C — press ⌘C again to attach clipboard to context")
        }
    }

    private func attachMostRecentClipboardText() {
        let pasteboard = NSPasteboard.general

        if pasteboard.types?.contains(where: Self.isConcealedType) == true {
            print("[ClipboardMonitor] Double ⌘C — concealed pasteboard content, skipping")
            return
        }

        guard let text = Self.readString(from: pasteboard) else {
            print("[ClipboardMonitor] Double ⌘C — no plain-text content on pasteboard")
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        print(
            "[ClipboardMonitor] Double ⌘C — attaching \(Self.describe(text)) from \(sourceApp?.localizedName ?? "unknown")"
        )
        onAttachFromClipboard?(text, sourceApp)
    }

    nonisolated private static func isConcealedType(_ type: NSPasteboard.PasteboardType) -> Bool {
        type.rawValue == "org.nspasteboard.ConcealedTypePlaceholder"
    }

    nonisolated private static func shouldIgnoreCopyShortcut() -> Bool {
        guard let ignoreCopyShortcutUntil else { return false }
        if Date() >= ignoreCopyShortcutUntil {
            Self.ignoreCopyShortcutUntil = nil
            return false
        }
        return true
    }
}
