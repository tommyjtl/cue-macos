import AppKit
import Foundation

/// Attaches clipboard text to context when the user copies twice in quick succession.
/// Signals come from ⌘C key events and/or pasteboard changeCount updates (covers right-click Copy).
@MainActor
final class ClipboardMonitor {
    typealias Handler = @MainActor (_ text: String, _ sourceApp: NSRunningApplication?) -> Void
    typealias DebugLogHandler = @MainActor (_ message: String) -> Void

    struct PasteboardDiagnostic: Equatable {
        let changeCount: Int
        let typeLabels: [String]
        let plainTextPreview: String?
        let readFailureReason: String?

        var logSummary: String {
            var parts = ["changeCount=\(changeCount)"]

            if typeLabels.isEmpty {
                parts.append("types=(none)")
            } else {
                parts.append("types=[\(typeLabels.joined(separator: ", "))]")
            }

            if let plainTextPreview {
                parts.append("text=\(plainTextPreview)")
            } else if let readFailureReason {
                parts.append("text=(unreadable: \(readFailureReason))")
            }

            return parts.joined(separator: " ")
        }
    }

    private enum DoubleCopyConfig {
        static let copyKeyCode: UInt16 = 8
        static let maxIntervalBetweenCopies: CFTimeInterval = 0.5
        static let pasteboardReadDelay: Duration = .milliseconds(100)
        static let pasteboardPollInterval: Duration = .milliseconds(250)
    }

    private let permissionManager = PermissionManager.shared
    private var globalCopyMonitor: Any?
    private var localCopyMonitor: Any?
    private var pasteboardWatchTask: Task<Void, Never>?
    private var lastCopySignalAt: CFTimeInterval?
    private var lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
    private var lastLoggedMonitorStatus: String?
    private var onAttachFromClipboard: Handler?
    private var onDebugLog: DebugLogHandler?

    nonisolated(unsafe) private static var ignoreCopyShortcutUntil: Date?

    nonisolated static let plainTextTypeCandidates: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("NSStringPboardType")
    ]

    func start(onAttachFromClipboard: @escaping Handler, onDebugLog: DebugLogHandler? = nil) {
        guard self.onAttachFromClipboard == nil else { return }

        self.onAttachFromClipboard = onAttachFromClipboard
        self.onDebugLog = onDebugLog
        lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
        installCopyMonitors()
        startPasteboardWatchLoop()
        logMonitorStatus(prefix: "Started", force: true)
        print("[ClipboardMonitor] Started — attach on double copy (⌘C or pasteboard change)")
    }

    func stop() {
        pasteboardWatchTask?.cancel()
        pasteboardWatchTask = nil
        removeCopyMonitors()
        onAttachFromClipboard = nil
        onDebugLog = nil
        lastCopySignalAt = nil
    }

    func refreshAccessibilityDependentMonitors() {
        if permissionManager.hasAccessibilityPermission() {
            installGlobalCopyMonitorIfNeeded()
        } else {
            removeGlobalCopyMonitor()
            logDebug("Accessibility not granted — ⌘C detection works only while Cue is focused; pasteboard watching stays active")
            print("[ClipboardMonitor] Accessibility not granted — ⌘C detection works only while Cue is focused")
        }

        logMonitorStatus(prefix: "Monitors refreshed")
    }

    nonisolated static func temporarilyIgnoreCopyShortcut(for interval: TimeInterval = 0.35) {
        ignoreCopyShortcutUntil = Date().addingTimeInterval(interval)
    }

    nonisolated static func isCopyKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        guard !event.modifierFlags.contains(.option) else { return false }
        guard !event.isARepeat else { return false }

        if event.keyCode == DoubleCopyConfig.copyKeyCode {
            return true
        }

        return event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    nonisolated static func readString(from pasteboard: NSPasteboard) -> String? {
        for type in plainTextTypeCandidates {
            guard pasteboard.availableType(from: [type]) == type,
                  let value = pasteboard.string(forType: type) else {
                continue
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    nonisolated static func diagnosePasteboard(_ pasteboard: NSPasteboard = .general) -> PasteboardDiagnostic {
        let typeLabels = pasteboard.types?.map(\.rawValue) ?? []

        if typeLabels.contains(where: { isConcealedType(NSPasteboard.PasteboardType($0)) }) {
            return PasteboardDiagnostic(
                changeCount: pasteboard.changeCount,
                typeLabels: typeLabels,
                plainTextPreview: nil,
                readFailureReason: "concealed pasteboard content"
            )
        }

        if let text = readString(from: pasteboard) {
            return PasteboardDiagnostic(
                changeCount: pasteboard.changeCount,
                typeLabels: typeLabels,
                plainTextPreview: preview(text),
                readFailureReason: nil
            )
        }

        let readFailureReason: String
        if typeLabels.isEmpty {
            readFailureReason = "pasteboard is empty"
        } else {
            readFailureReason = "no supported plain-text type"
        }

        return PasteboardDiagnostic(
            changeCount: pasteboard.changeCount,
            typeLabels: typeLabels,
            plainTextPreview: nil,
            readFailureReason: readFailureReason
        )
    }

    nonisolated static func describe(_ text: String?) -> String {
        guard let text else { return "nil" }
        return "\"\(preview(text))\" (\(text.count) chars)"
    }

    nonisolated static func preview(_ text: String, limit: Int = 80) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    nonisolated static func shouldAttachAfterCopySignal(
        lastCopySignalAt: CFTimeInterval?,
        now: CFTimeInterval,
        maxIntervalBetweenCopies: CFTimeInterval = DoubleCopyConfig.maxIntervalBetweenCopies
    ) -> (nextLastCopySignalAt: CFTimeInterval?, shouldAttach: Bool) {
        if let lastCopySignalAt,
           now - lastCopySignalAt <= maxIntervalBetweenCopies {
            return (nil, true)
        }

        return (now, false)
    }

    private func installCopyMonitors() {
        if localCopyMonitor == nil {
            localCopyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in
                    self?.handleCopyKeyDown(event, monitor: "local")
                }
                return event
            }
        }

        installGlobalCopyMonitorIfNeeded()
    }

    private func installGlobalCopyMonitorIfNeeded() {
        guard permissionManager.hasAccessibilityPermission() else { return }
        guard globalCopyMonitor == nil else { return }

        globalCopyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleCopyKeyDown(event, monitor: "global")
            }
        }

        if globalCopyMonitor != nil {
            print("[ClipboardMonitor] Global ⌘C monitor active")
        } else {
            logDebug("Failed to install global ⌘C monitor — pasteboard watching still active")
            print("[ClipboardMonitor] Failed to install global ⌘C monitor")
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

    private func startPasteboardWatchLoop() {
        pasteboardWatchTask?.cancel()
        pasteboardWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: DoubleCopyConfig.pasteboardPollInterval)
                await self?.checkPasteboardForChanges()
            }
        }
    }

    private func checkPasteboardForChanges() {
        guard !Task.isCancelled else { return }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedPasteboardChangeCount else { return }

        lastObservedPasteboardChangeCount = changeCount
        guard !Self.shouldIgnoreCopyShortcut() else { return }

        let diagnostic = Self.diagnosePasteboard(pasteboard)
        handleCopySignal(source: "pasteboard", monitor: nil, diagnostic: diagnostic)
    }

    private func handleCopyKeyDown(_ event: NSEvent, monitor: String) {
        guard Self.isCopyKeyDown(event) else { return }

        let diagnostic = Self.diagnosePasteboard()
        handleCopySignal(source: "⌘C", monitor: monitor, diagnostic: diagnostic)
    }

    private func handleCopySignal(source: String, monitor: String?, diagnostic: PasteboardDiagnostic) {
        let now = CFAbsoluteTimeGetCurrent()
        let decision = Self.shouldAttachAfterCopySignal(lastCopySignalAt: lastCopySignalAt, now: now)
        lastCopySignalAt = decision.nextLastCopySignalAt

        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let viaMonitor = monitor.map { " via \($0) monitor" } ?? ""

        if decision.shouldAttach {
            logDebug("Second copy signal from \(source)\(viaMonitor) in \(frontmostApp) — attaching")
            print("[ClipboardMonitor] Second copy signal — attaching")
            Task { @MainActor in
                try? await Task.sleep(for: DoubleCopyConfig.pasteboardReadDelay)
                attachMostRecentClipboardText(sourceLabel: source, frontmostAppName: frontmostApp)
            }
            return
        }

        logDebug("First copy signal from \(source)\(viaMonitor) in \(frontmostApp) — copy again within 0.5s to attach")
        print("[ClipboardMonitor] First copy signal — copy again to attach")

        Task { @MainActor in
            try? await Task.sleep(for: DoubleCopyConfig.pasteboardReadDelay)
            let refreshed = Self.diagnosePasteboard()
            logDebug("Clipboard snapshot after first copy: \(refreshed.logSummary)")
        }
    }

    private func attachMostRecentClipboardText(sourceLabel: String, frontmostAppName: String) {
        let diagnostic = Self.diagnosePasteboard()

        if diagnostic.readFailureReason == "concealed pasteboard content" {
            logDebug("Attach from \(sourceLabel) in \(frontmostAppName) skipped concealed pasteboard content")
            print("[ClipboardMonitor] Attach skipped concealed pasteboard content")
            return
        }

        guard let text = Self.readString(from: .general) else {
            logDebug("Attach from \(sourceLabel) in \(frontmostAppName) found no readable text — \(diagnostic.logSummary)")
            print("[ClipboardMonitor] Attach failed — no plain-text content on pasteboard")
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        logDebug("Attached \(Self.describe(text)) from \(sourceApp?.localizedName ?? frontmostAppName)")
        print(
            "[ClipboardMonitor] Attached \(Self.describe(text)) from \(sourceApp?.localizedName ?? "unknown")"
        )
        onAttachFromClipboard?(text, sourceApp)
    }

    private func monitorStatusMessage(prefix: String) -> String {
        "\(prefix) — local monitor=\(localCopyMonitor != nil), global monitor=\(globalCopyMonitor != nil), pasteboard watch=active, accessibility=\(permissionManager.hasAccessibilityPermission())"
    }

    private func logMonitorStatus(prefix: String, force: Bool = false) {
        let message = monitorStatusMessage(prefix: prefix)
        guard force || message != lastLoggedMonitorStatus else { return }
        lastLoggedMonitorStatus = message
        logDebug(message)
    }

    private func logDebug(_ message: String) {
        onDebugLog?(message)
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
