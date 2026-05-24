import AppKit
import ApplicationServices
import Foundation

@MainActor
final class SelectedTextManager {
    enum LoggingMode {
        case silent
        case concise
        case verbose
    }

    struct SelectionSnapshot {
        let createdAt: Date
        let text: String
        let appName: String?
        let bundleIdentifier: String?
        let role: String?
        let subrole: String?
    }

    enum SelectionError: LocalizedError {
        case accessibilityPermissionRequired
        case noFocusedElement
        case unsupportedElement(role: String?, subrole: String?)
        case noSelectedText
        case apiFailure(String)

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to inspect selected text."
            case .noFocusedElement:
                return "Cue could not find the currently focused UI element."
            case let .unsupportedElement(role, subrole):
                let roleDescription = role ?? "unknown"
                let subroleDescription = subrole ?? "none"
                return "The focused element does not expose selected text. role=\(roleDescription) subrole=\(subroleDescription)"
            case .noSelectedText:
                return "No selected text was available from the focused element."
            case let .apiFailure(message):
                return message
            }
        }
    }

    private let permissionManager = PermissionManager.shared

    func captureSelectedText(
        promptForPermission: Bool = true,
        loggingMode: LoggingMode = .concise
    ) throws -> SelectionSnapshot {
        log("Starting selected-text detection.", mode: loggingMode, minimumMode: .verbose)

        guard permissionManager.ensureAccessibilityPermission(promptIfNeeded: promptForPermission) else {
            log("Accessibility permission is not currently granted.", mode: loggingMode)
            throw SelectionError.accessibilityPermissionRequired
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        log(
            "Frontmost app: \(frontmostApplication?.localizedName ?? "unknown") bundleID=\(frontmostApplication?.bundleIdentifier ?? "unknown")",
            mode: loggingMode,
            minimumMode: .verbose
        )

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedElement = copyAXElementAttribute(
            systemWideElement,
            attribute: kAXFocusedUIElementAttribute as CFString,
            loggingMode: loggingMode
        ) else {
            log("Unable to resolve the focused accessibility element.", mode: loggingMode)
            throw SelectionError.noFocusedElement
        }

        let role = copyStringAttribute(
            focusedElement,
            attribute: kAXRoleAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        )
        let subrole = copyStringAttribute(
            focusedElement,
            attribute: kAXSubroleAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        )
        log(
            "Focused element role=\(role ?? "unknown") subrole=\(subrole ?? "none")",
            mode: loggingMode,
            minimumMode: .verbose
        )

        if let selectedText = copyStringAttribute(
            focusedElement,
            attribute: kAXSelectedTextAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        ) {
            let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                log("Selected text detected (\(trimmedText.count) chars).", mode: loggingMode)
                return SelectionSnapshot(
                    createdAt: Date(),
                    text: trimmedText,
                    appName: frontmostApplication?.localizedName,
                    bundleIdentifier: frontmostApplication?.bundleIdentifier,
                    role: role,
                    subrole: subrole
                )
            }

            log(
                "Focused element exposes selected text, but it is empty after trimming.",
                mode: loggingMode,
                minimumMode: .verbose
            )
            throw SelectionError.noSelectedText
        }

        if let selectedRange = copySelectedTextRange(focusedElement) {
            if selectedRange.length > 0 {
                log(
                    "Focused element exposes a selected text range but not selected text directly. location=\(selectedRange.location) length=\(selectedRange.length)",
                    mode: loggingMode
                )
            } else {
                log("Focused element reports no selected text.", mode: loggingMode, minimumMode: .verbose)
            }
            throw SelectionError.unsupportedElement(role: role, subrole: subrole)
        }

        log("Focused element does not expose selected text attributes.", mode: loggingMode, minimumMode: .verbose)
        throw SelectionError.unsupportedElement(role: role, subrole: subrole)
    }

    private func copyAXElementAttribute(
        _ element: AXUIElement,
        attribute: CFString,
        loggingMode: LoggingMode
    ) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            log("AX copy attribute failed for \(attribute) with error=\(error.rawValue)", mode: loggingMode)
            return nil
        }

        guard let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            log("AX attribute \(attribute) returned a non-AXUIElement value.", mode: loggingMode)
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyStringAttribute(
        _ element: AXUIElement,
        attribute: CFString,
        loggingMode: LoggingMode,
        logExpectedFailure: Bool
    ) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            if logExpectedFailure {
                log("AX string attribute \(attribute) unavailable, error=\(error.rawValue)", mode: loggingMode)
            } else {
                log(
                    "AX string attribute \(attribute) unavailable, error=\(error.rawValue)",
                    mode: loggingMode,
                    minimumMode: .verbose
                )
            }
            return nil
        }

        return value as? String
    }

    private func copySelectedTextRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func log(_ message: String, mode: LoggingMode, minimumMode: LoggingMode = .concise) {
        guard mode.rank >= minimumMode.rank else {
            return
        }

        print("[SelectedTextManager] \(message)")
    }
}

private extension SelectedTextManager.LoggingMode {
    var rank: Int {
        switch self {
        case .silent:
            0
        case .concise:
            1
        case .verbose:
            2
        }
    }
}