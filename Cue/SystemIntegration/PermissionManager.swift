import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Central permission state for Cue. Use `PermissionManager.shared` everywhere so
/// TCC checks are coalesced and we never spam ScreenCaptureKit on a timer.
@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    private enum UserDefaultsKey {
        static let lastVerifiedScreenCaptureFingerprint = "last-verified-screen-capture-fingerprint"
    }

    private enum SCKErrorCode {
        static let userDeclined = -3801
    }

    private(set) var screenCaptureGranted = false
    private var sckVerificationTask: Task<Bool, Never>?
    private var lastSCKVerificationAt: Date?
    private var hasRegisteredForScreenCapture = false
    private(set) var lastPermissionSettingsOpenedAt: Date?

    private init() {}

    // MARK: - Screen Recording

    /// Cheap read for UI. Does not call ScreenCaptureKit.
    func hasScreenCapturePermission() -> Bool {
        screenCaptureGranted || CGPreflightScreenCaptureAccess()
    }

    /// ScreenCaptureKit shareable content for capture flows. Uses the same API as permission verification.
    func fetchShareableContent(onScreenWindowsOnly: Bool = true) async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: onScreenWindowsOnly)
    }

    /// Authoritative ScreenCaptureKit check. Coalesced — concurrent callers share one request.
    @discardableResult
    func verifyScreenCaptureAccess(force: Bool = false) async -> Bool {
        if !force,
           let lastSCKVerificationAt,
           Date().timeIntervalSince(lastSCKVerificationAt) < 3 {
            return screenCaptureGranted
        }

        if CGPreflightScreenCaptureAccess() {
            markScreenCaptureGranted()
            return true
        }

        if let sckVerificationTask {
            return await sckVerificationTask.value
        }

        let task = Task { @MainActor in
            defer { self.sckVerificationTask = nil }

            do {
                _ = try await self.fetchShareableContent(onScreenWindowsOnly: false)
                self.markScreenCaptureGranted()
                print("[PermissionManager] verifyScreenCaptureAccess: granted (bundle=\(Bundle.main.bundleIdentifier ?? "?") path=\(self.runningApplicationPath))")
                return true
            } catch {
                self.lastSCKVerificationAt = Date()
                let nsError = error as NSError
                print("[PermissionManager] verifyScreenCaptureAccess: denied — domain=\(nsError.domain) code=\(nsError.code) (\(error.localizedDescription)) path=\(self.runningApplicationPath)")

                if nsError.domain == SCStreamErrorDomain, nsError.code == SCKErrorCode.userDeclined {
                    self.screenCaptureGranted = false
                }

                return self.screenCaptureGranted
            }
        }

        sckVerificationTask = task
        return await task.value
    }

    /// Registers this binary in System Settings > Screen Recording. Call once at launch.
    func registerScreenCaptureIfNeeded() async {
        guard !hasRegisteredForScreenCapture else { return }
        hasRegisteredForScreenCapture = true

        print("[PermissionManager] registerScreenCaptureIfNeeded: CGPreflight=\(CGPreflightScreenCaptureAccess()) fingerprint=\(executableFingerprint())")
        _ = await verifyScreenCaptureAccess(force: true)
    }

    /// User-initiated grant flow. May show the system permission sheet once.
    func requestScreenCapturePermission() async {
        markPermissionSettingsOpened()

        if await verifyScreenCaptureAccess(force: true) {
            return
        }

        _ = CGRequestScreenCaptureAccess()
        try? await Task.sleep(for: .milliseconds(400))
        _ = await verifyScreenCaptureAccess(force: true)

        if !hasScreenCapturePermission() {
            openSystemPrivacySettings(pane: "Privacy_ScreenCapture")
        }
    }

    func openScreenCaptureSettings() {
        markPermissionSettingsOpened()
        openSystemPrivacySettings(pane: "Privacy_ScreenCapture")
    }

    func markPermissionSettingsOpened() {
        lastPermissionSettingsOpenedAt = Date()
    }

    /// Screen Recording usually needs a new process after granting. Accessibility often updates live.
    var needsRestartAfterPermissionChange: Bool {
        guard let lastPermissionSettingsOpenedAt else { return false }
        guard Date().timeIntervalSince(lastPermissionSettingsOpenedAt) < 600 else { return false }
        return !hasScreenCapturePermission()
    }

    enum LaunchContext: Equatable {
        case xcodeDebug
        case xcodeArchive
        case installed
        case other

        static func current(for bundlePath: String) -> LaunchContext {
            if bundlePath.contains("/DerivedData/"), bundlePath.contains("/Build/Products/") {
                return .xcodeDebug
            }
            if bundlePath.contains(".xcarchive/") {
                return .xcodeArchive
            }
            if bundlePath.hasPrefix("/Applications/") {
                return .installed
            }
            return .other
        }
    }

    var launchContext: LaunchContext {
        LaunchContext.current(for: runningApplicationPath)
    }

    var restartAfterPermissionChangeHint: String {
        switch launchContext {
        case .xcodeDebug:
            return """
            Screen Recording applies on the next launch from Xcode — not via System Settings' "Quit & Reopen".

            1. Stop Cue in Xcode (⌘. or ⌘Q)
            2. Press Run (⌘R)

            Do not use System Settings' Quit & Reopen while debugging; it can relaunch the wrong copy of Cue.

            Running from:
            \(runningApplicationPath)
            """
        case .xcodeArchive:
            return """
            Quit Cue (⌘Q), then reopen this app from Finder. Do not use System Settings' Quit & Reopen.

            Running from:
            \(runningApplicationPath)
            """
        case .installed:
            return """
            Quit Cue (⌘Q), then open it again from Applications.

            Running from:
            \(runningApplicationPath)
            """
        case .other:
            return """
            Quit Cue (⌘Q), then reopen it. Do not use System Settings' Quit & Reopen.

            Running from:
            \(runningApplicationPath)
            """
        }
    }

    var enablePermissionsHint: String {
        let restartNote = launchContext == .xcodeDebug
            ? "After enabling Screen Recording, stop the app in Xcode (⌘.) and Run (⌘R) — not System Settings' Quit & Reopen."
            : "After enabling Screen Recording, quit Cue (⌘Q) and reopen it."

        return """
        Click Enable… for each permission and turn on Cue.app in System Settings. Accessibility usually updates here immediately; Screen Recording needs a relaunch.

        \(restartNote)

        Running from:
        \(runningApplicationPath)
        """
    }

    /// True when System Settings may show Cue as enabled but this binary is not authorized.
    var hasStaleScreenCaptureGrant: Bool {
        guard isLikelyEligibleForScreenCaptureGrant else { return false }
        guard !hasScreenCapturePermission() else { return false }
        guard let stored = UserDefaults.standard.string(forKey: UserDefaultsKey.lastVerifiedScreenCaptureFingerprint) else {
            return false
        }

        let current = executableFingerprint()
        if CodeSigningDiagnostics.fingerprintsMatch(stored, current) {
            migrateStoredScreenCaptureFingerprintIfNeeded(from: stored, to: current)
            return false
        }

        return true
    }

    var unsignedBuildHint: String {
        """
        This copy of Cue is not signed with an Apple Developer ID certificate. On macOS 15+, Screen Recording and Accessibility will not work — System Settings may show Cue as enabled, but the app cannot receive permission.

        GitHub release DMGs must be built with code signing enabled. If you installed an older unsigned release, delete /Applications/Cue.app and install a signed build.
        """
    }

    var staleScreenCaptureRecoveryHint: String {
        """
        macOS tied Screen Recording to a different build of Cue. Toggle Cue.app off and on in System Settings, or reset with:

        tccutil reset ScreenCapture com.cruxbetalabs.Cue

        Then quit Cue (⌘Q), reopen, and enable again for this copy:

        \(runningApplicationPath)
        """
    }

    var crossAppAccessibilityRecoveryHint: String {
        """
        Cue appears trusted, but macOS is blocking cross-app Accessibility (Safari, Chrome, Obsidian, etc.). Terminal may still work.

        Quit Cue (⌘Q), then run:

        tccutil reset Accessibility com.cruxbetalabs.Cue

        Reopen Cue from Applications — not from Terminal or iTerm — and enable Cue.app in System Settings → Accessibility. Confirm Cue.app appears in that list.

        Running from:
        \(runningApplicationPath)
        """
    }

    // MARK: - Accessibility

    func hasAccessibilityPermission() -> Bool {
        AccessibilityClient.isProcessTrusted()
    }

    /// True when Accessibility is granted and Cue can query at least one other running app's AX tree.
    func canReadOtherApplicationsAccessibilityTree() -> Bool {
        AccessibilityClient.canQueryOtherApplicationsTree()
    }

    func requestAccessibilityPermission() {
        markPermissionSettingsOpened()

        if hasAccessibilityPermission() {
            return
        }

        if !AccessibilityClient.isProcessTrusted(prompt: true) {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        markPermissionSettingsOpened()
        openSystemPrivacySettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Diagnostics

    var runningApplicationPath: String {
        Bundle.main.bundlePath
    }

    var isLikelyEligibleForScreenCaptureGrant: Bool {
        if case .signed = codeSigningStatus() {
            return true
        }
        return false
    }

    typealias CodeSigningStatus = CodeSigningDiagnostics.Status

    func codeSigningStatus() -> CodeSigningStatus {
        CodeSigningDiagnostics.status(forBundleAt: runningApplicationPath)
    }

    func executableFingerprint() -> String {
        CodeSigningDiagnostics.fingerprint(forBundleAt: runningApplicationPath)
    }

    func permissionDiagnosticsSummary() -> String {
        let ax = hasAccessibilityPermission()
        let axLive = AccessibilityClient.canCreateListenOnlyEventTap()
        let sr = hasScreenCapturePermission()
        let preflight = CGPreflightScreenCaptureAccess()
        return "AX=\(ax) AXLive=\(axLive) SR=\(sr) CGPreflight=\(preflight) fingerprint=\(executableFingerprint())"
    }

    // MARK: - Private

    private func markScreenCaptureGranted() {
        screenCaptureGranted = true
        lastSCKVerificationAt = Date()
        UserDefaults.standard.set(executableFingerprint(), forKey: UserDefaultsKey.lastVerifiedScreenCaptureFingerprint)
    }

    private func migrateStoredScreenCaptureFingerprintIfNeeded(from stored: String, to current: String) {
        guard stored != current else { return }
        UserDefaults.standard.set(current, forKey: UserDefaultsKey.lastVerifiedScreenCaptureFingerprint)
    }

    private func openSystemPrivacySettings(pane: String) {
        let urlString: String
        if #available(macOS 13, *) {
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
