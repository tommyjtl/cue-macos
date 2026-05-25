import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

/// Thin wrappers around macOS Accessibility APIs used by Cue.
enum AccessibilityClient {
    private static let eventTapCallback: CGEventTapCallBack = { _, _, event, _ in
        Unmanaged.passUnretained(event)
    }

    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        guard prompt else {
            return resolveTrustedState()
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return resolveTrustedState()
    }

    /// Trust `AXIsProcessTrusted()` when true. The listen-only event tap is kept for
    /// diagnostics only — it can fail on valid installs (especially after replacing the app)
    /// even while Accessibility APIs work.
    static func resolveTrustedState(cachedTrusted: Bool = AXIsProcessTrusted(), liveTrusted: Bool = canCreateListenOnlyEventTap()) -> Bool {
        if cachedTrusted {
            return true
        }
        return liveTrusted
    }

    static func canCreateListenOnlyEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }

    /// True when Accessibility is granted and Cue can query at least one other running app's AX tree.
    /// Returns true when no other regular apps are running (nothing to probe).
    static func canQueryOtherApplicationsTree() -> Bool {
        guard resolveTrustedState() else { return false }

        var probedAnyOtherApp = false
        var queriedAnySuccessfully = false

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else {
                continue
            }

            probedAnyOtherApp = true
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if copyAttributeValue(appElement, attribute: kAXWindowsAttribute as CFString) != nil {
                queriedAnySuccessfully = true
                break
            }
        }

        return canQueryOtherApplicationsTree(
            probedOtherApp: probedAnyOtherApp,
            queriedAnySuccessfully: queriedAnySuccessfully
        )
    }

    static func canQueryOtherApplicationsTree(probedOtherApp: Bool, queriedAnySuccessfully: Bool) -> Bool {
        if queriedAnySuccessfully {
            return true
        }
        return !probedOtherApp
    }

    static func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        copyAttributeValue(element, attribute: attribute) as? String
    }

    static func copyElementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let value = copyAttributeValue(element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    static func copyCFRangeAttribute(_ element: AXUIElement, attribute: CFString) -> CFRange? {
        guard let value = copyAttributeValue(element, attribute: attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    static func copyParameterizedString(
        _ element: AXUIElement,
        attribute: CFString,
        range: CFRange
    ) -> String? {
        var cfRange = range
        guard let axValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute,
            axValue,
            &result
        )
        guard error == .success else {
            return nil
        }

        return result as? String
    }

    private static func copyAttributeValue(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return nil
        }

        return value
    }
}
