import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class PermissionManager {
    private enum UserDefaultsKey {
        static let hasPromptedForAccessibilityPermission = "has-prompted-for-accessibility-permission"
    }

    // MARK: - Screen Recording

    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Silently probes SCK on launch so the app registers itself in the
    /// System Settings > Screen Recording list without opening any UI.
    func probeScreenCaptureKitSilently() async {
        let preflightBefore = CGPreflightScreenCaptureAccess()
        print("[PermissionManager] probeScreenCaptureKitSilently: CGPreflightScreenCaptureAccess=\(preflightBefore)  bundle=\(Bundle.main.bundleIdentifier ?? "?")")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            print("[PermissionManager] probeScreenCaptureKitSilently: SCK call succeeded, \(content.displays.count) display(s) — screen recording is granted")
        } catch {
            let nsError = error as NSError
            print("[PermissionManager] probeScreenCaptureKitSilently: SCK call threw — domain=\(nsError.domain) code=\(nsError.code) (\(error.localizedDescription)) — this is expected before permission is granted; the app should now appear in System Settings > Screen Recording")
        }
    }

    /// Called when the user explicitly asks to grant Screen Recording permission.
    /// CGRequestScreenCaptureAccess() on macOS 14+ both registers the app in
    /// System Settings > Screen & System Audio Recording AND opens System Settings
    /// so the user can toggle it on — even if the app wasn't in the list before.
    /// The SCK call is a secondary belt-and-suspenders registration attempt.
    func requestScreenCaptureViaScreenCaptureKit() async {
        let cgResult = CGRequestScreenCaptureAccess()
        print("[PermissionManager] requestScreenCaptureViaScreenCaptureKit: CGRequestScreenCaptureAccess()=\(cgResult)")
        // Belt-and-suspenders: also trigger the SCK TCC path.
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        // CGRequestScreenCaptureAccess already opens System Settings on macOS 14+.
        // Fall back to URL navigation only if it somehow didn't.
        if !hasScreenCapturePermission() && !cgResult {
            openScreenCaptureSettings()
        }
    }

    func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func openScreenCaptureSettings() {
        openSystemPrivacySettings(pane: "Privacy_ScreenCapture")
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

    func openAccessibilitySettings() {
        openSystemPrivacySettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Helpers

    private func openSystemPrivacySettings(pane: String) {
        // macOS 13+ moved to System Settings; use the new extension-based URL.
        // The old com.apple.preference.security path is no longer reliable on macOS 26.
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