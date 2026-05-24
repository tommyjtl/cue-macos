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
        static let hasPromptedForAccessibilityPermission = "has-prompted-for-accessibility-permission"
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
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                self.markScreenCaptureGranted()
                print("[PermissionManager] verifyScreenCaptureAccess: granted (bundle=\(Bundle.main.bundleIdentifier ?? "?") path=\(self.runningApplicationPath))")
                return true
            } catch {
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
        let stored = UserDefaults.standard.string(forKey: UserDefaultsKey.lastVerifiedScreenCaptureFingerprint)
        let current = executableFingerprint()
        return stored != nil && stored != current
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

    // MARK: - Accessibility

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func ensureAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if hasAccessibilityPermission() {
            return true
        }

        guard promptIfNeeded else {
            return false
        }

        guard !UserDefaults.standard.bool(forKey: UserDefaultsKey.hasPromptedForAccessibilityPermission) else {
            return false
        }

        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasPromptedForAccessibilityPermission)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermission() {
        markPermissionSettingsOpened()

        if hasAccessibilityPermission() {
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
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

    enum CodeSigningStatus: Equatable {
        case signed(teamID: String)
        case unsigned
    }

    func codeSigningStatus() -> CodeSigningStatus {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", runningApplicationPath]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .unsigned
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if output.contains("Signature=adhoc") {
            return .unsigned
        }

        for line in output.split(separator: "\n") {
            guard line.contains("TeamIdentifier=") else { continue }
            let teamID = line.split(separator: "=", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !teamID.isEmpty {
                return .signed(teamID: teamID)
            }
        }

        return .unsigned
    }

    func executableFingerprint() -> String {
        let dylibPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/Cue.debug.dylib")
            .path
        if FileManager.default.fileExists(atPath: dylibPath) {
            return "dylib:\(codesignLine(from: dylibPath, prefix: "CDHash=") ?? dylibPath)"
        }
        return codesignLine(from: runningApplicationPath, prefix: "CDHash=") ?? runningApplicationPath
    }

    func permissionDiagnosticsSummary() -> String {
        let ax = hasAccessibilityPermission()
        let sr = hasScreenCapturePermission()
        let preflight = CGPreflightScreenCaptureAccess()
        return "AX=\(ax) SR=\(sr) CGPreflight=\(preflight) fingerprint=\(executableFingerprint())"
    }

    // MARK: - Private

    private func markScreenCaptureGranted() {
        screenCaptureGranted = true
        lastSCKVerificationAt = Date()
        UserDefaults.standard.set(executableFingerprint(), forKey: UserDefaultsKey.lastVerifiedScreenCaptureFingerprint)
    }

    private func codesignLine(from path: String, prefix: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvvv", path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            guard line.contains(prefix) else { continue }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
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
