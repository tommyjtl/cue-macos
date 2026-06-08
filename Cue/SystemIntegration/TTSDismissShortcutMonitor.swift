import AppKit
import Foundation

/// Listens for the configured dismiss shortcut (default: double Escape) and cancels active TTS work.
@MainActor
final class TTSDismissShortcutMonitor {
    typealias ShouldCancelHandler = @MainActor () -> Bool
    typealias CancelHandler = @MainActor () -> Void

    private let permissionManager = PermissionManager.shared
    private var dismissShortcut: DismissChatShortcut
    private var pressTracker = RepeatedKeyPressTracker()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let shouldCancel: ShouldCancelHandler
    private let onCancel: CancelHandler

    init(
        dismissShortcut: DismissChatShortcut,
        shouldCancel: @escaping ShouldCancelHandler,
        onCancel: @escaping CancelHandler
    ) {
        self.dismissShortcut = dismissShortcut.normalized
        self.shouldCancel = shouldCancel
        self.onCancel = onCancel
    }

    func start() {
        guard localMonitor == nil else { return }
        installLocalMonitorIfNeeded()
        installGlobalMonitorIfNeeded()
    }

    func stop() {
        removeMonitors()
        pressTracker.reset()
    }

    func updateDismissShortcut(_ shortcut: DismissChatShortcut) {
        dismissShortcut = shortcut.normalized
        pressTracker.reset()
    }

    func refreshAccessibilityDependentMonitors() {
        if permissionManager.hasAccessibilityPermission() {
            installGlobalMonitorIfNeeded()
            return
        }

        removeGlobalMonitor()
    }

    private func installLocalMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func installGlobalMonitorIfNeeded() {
        guard permissionManager.hasAccessibilityPermission() else { return }
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }
    }

    private func removeGlobalMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        removeGlobalMonitor()
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard dismissShortcut.matches(event) else { return false }
        guard shouldCancel() else { return false }
        guard pressTracker.registerPress(shortcut: dismissShortcut) else { return false }

        onCancel()
        return true
    }
}
