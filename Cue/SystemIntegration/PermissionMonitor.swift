import AppKit
import Foundation

/// Coalesces permission refresh triggers (AX notifications, app activation, polling)
/// so Cue does not run redundant ScreenCaptureKit verification in parallel.
@MainActor
final class PermissionMonitor {
    typealias RefreshHandler = @MainActor (PermissionManager) async -> Void

    private var monitorTask: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?

    func start(refresh: @escaping RefreshHandler) {
        guard monitorTask == nil else { return }

        monitorTask = Task {
            let permManager = PermissionManager.shared

            try? await Task.sleep(for: .milliseconds(500))
            await permManager.registerScreenCaptureIfNeeded()
            await refresh(permManager)

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.axNotificationLoop(refresh: refresh) }
                group.addTask { await self.applicationActiveLoop(refresh: refresh) }
                group.addTask { await self.pollLoop(refresh: refresh) }
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
    }

    // MARK: - Loops

    private func axNotificationLoop(refresh: @escaping RefreshHandler) async {
        let stream = Self.axPermissionNotificationStream()
        for await _ in stream {
            guard !Task.isCancelled else { return }
            scheduleDebouncedRefresh(delay: .milliseconds(500), verifyScreenCapture: false, refresh: refresh)
        }
    }

    private func applicationActiveLoop(refresh: @escaping RefreshHandler) async {
        for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
            guard !Task.isCancelled else { return }
            scheduleDebouncedRefresh(delay: .milliseconds(400), verifyScreenCapture: true, refresh: refresh)
        }
    }

    private func pollLoop(refresh: @escaping RefreshHandler) async {
        let permManager = PermissionManager.shared

        while !Task.isCancelled {
            await refresh(permManager)

            let allGranted = permManager.hasScreenCapturePermission()
                && permManager.hasAccessibilityPermission()
            let delay: Duration = allGranted ? .seconds(2) : .milliseconds(500)
            try? await Task.sleep(for: delay)
        }
    }

    private func scheduleDebouncedRefresh(
        delay: Duration,
        verifyScreenCapture: Bool,
        refresh: @escaping RefreshHandler
    ) {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            let permManager = PermissionManager.shared
            if verifyScreenCapture {
                print("[PermissionMonitor] didBecomeActive — \(permManager.permissionDiagnosticsSummary())")
                await permManager.verifyScreenCaptureAccess(force: true)
            }

            await refresh(permManager)
        }
    }

    private static func axPermissionNotificationStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            print("[PermissionMonitor] Registered observer for com.apple.accessibility.api")
            let observer = center.addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                center.removeObserver(observer)
            }
        }
    }
}
