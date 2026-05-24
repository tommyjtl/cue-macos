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
    private let maxParentTraversalDepth = 10

    func captureSelectedText(
        promptForPermission: Bool = true,
        loggingMode: LoggingMode = .concise
    ) throws -> SelectionSnapshot {
        log("Starting selected-text detection.", mode: loggingMode, minimumMode: .verbose)

        guard permissionManager.hasAccessibilityPermission() else {
            if promptForPermission {
                permissionManager.requestAccessibilityPermission()
            }
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
        let candidateElements = focusedElementCandidates(
            frontmostApplication: frontmostApplication,
            systemWideElement: systemWideElement,
            loggingMode: loggingMode
        )

        guard !candidateElements.isEmpty else {
            log("Unable to resolve any focused accessibility elements.", mode: loggingMode)
            throw SelectionError.noFocusedElement
        }

        for (index, element) in candidateElements.enumerated() {
            let role = copyStringAttribute(
                element,
                attribute: kAXRoleAttribute as CFString,
                loggingMode: loggingMode,
                logExpectedFailure: false
            )
            let subrole = copyStringAttribute(
                element,
                attribute: kAXSubroleAttribute as CFString,
                loggingMode: loggingMode,
                logExpectedFailure: false
            )
            log(
                "Candidate \(index + 1)/\(candidateElements.count) role=\(role ?? "unknown") subrole=\(subrole ?? "none")",
                mode: loggingMode,
                minimumMode: .verbose
            )

            if let selectedText = selectedText(from: element, loggingMode: loggingMode) {
                log("Selected text detected (\(selectedText.count) chars).", mode: loggingMode)
                return SelectionSnapshot(
                    createdAt: Date(),
                    text: selectedText,
                    appName: frontmostApplication?.localizedName,
                    bundleIdentifier: frontmostApplication?.bundleIdentifier,
                    role: role,
                    subrole: subrole
                )
            }
        }

        let primaryElement = candidateElements[0]
        let role = copyStringAttribute(
            primaryElement,
            attribute: kAXRoleAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        )
        let subrole = copyStringAttribute(
            primaryElement,
            attribute: kAXSubroleAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        )

        if let selectedRange = copySelectedTextRange(primaryElement), selectedRange.length > 0 {
            log(
                "Focused element exposes a selected text range but Cue could not resolve the text. location=\(selectedRange.location) length=\(selectedRange.length)",
                mode: loggingMode
            )
            throw SelectionError.unsupportedElement(role: role, subrole: subrole)
        }

        log("No selected text found across \(candidateElements.count) accessibility candidates.", mode: loggingMode, minimumMode: .verbose)
        throw SelectionError.noSelectedText
    }

    private func focusedElementCandidates(
        frontmostApplication: NSRunningApplication?,
        systemWideElement: AXUIElement,
        loggingMode: LoggingMode
    ) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        var seen = Set<ObjectIdentifier>()

        func appendRoot(_ element: AXUIElement?) {
            guard let element else { return }
            let key = ObjectIdentifier(element as AnyObject)
            guard seen.insert(key).inserted else { return }
            roots.append(element)
        }

        appendRoot(copyAXElementAttribute(
            systemWideElement,
            attribute: kAXFocusedUIElementAttribute as CFString,
            loggingMode: loggingMode
        ))

        if let pid = frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            appendRoot(copyAXElementAttribute(
                appElement,
                attribute: kAXFocusedUIElementAttribute as CFString,
                loggingMode: loggingMode
            ))

            if let focusedWindow = copyAXElementAttribute(
                appElement,
                attribute: kAXFocusedWindowAttribute as CFString,
                loggingMode: loggingMode
            ) {
                appendRoot(copyAXElementAttribute(
                    focusedWindow,
                    attribute: kAXFocusedUIElementAttribute as CFString,
                    loggingMode: loggingMode
                ))
            }
        }

        var candidates: [AXUIElement] = []
        var candidateSeen = Set<ObjectIdentifier>()

        func appendCandidate(_ element: AXUIElement) {
            let key = ObjectIdentifier(element as AnyObject)
            guard candidateSeen.insert(key).inserted else { return }
            candidates.append(element)
        }

        for root in roots {
            var current: AXUIElement? = root
            var depth = 0
            while let element = current, depth < maxParentTraversalDepth {
                appendCandidate(element)
                current = copyAXElementAttribute(
                    element,
                    attribute: kAXParentAttribute as CFString,
                    loggingMode: loggingMode
                )
                depth += 1
            }
        }

        return candidates
    }

    private func selectedText(from element: AXUIElement, loggingMode: LoggingMode) -> String? {
        if let direct = copyStringAttribute(
            element,
            attribute: kAXSelectedTextAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        ) {
            let trimmedText = direct.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                return trimmedText
            }
        }

        guard let selectedRange = copySelectedTextRange(element), selectedRange.length > 0 else {
            return nil
        }

        if let rangedText = copyStringForRange(element, range: selectedRange, loggingMode: loggingMode) {
            let trimmedText = rangedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                return trimmedText
            }
        }

        if let valueText = copyStringAttribute(
            element,
            attribute: kAXValueAttribute as CFString,
            loggingMode: loggingMode,
            logExpectedFailure: false
        ), selectedRange.length > 0 {
            let nsValue = valueText as NSString
            let safeLocation = min(max(selectedRange.location, 0), nsValue.length)
            let safeLength = min(max(selectedRange.length, 0), nsValue.length - safeLocation)
            if safeLength > 0 {
                let substring = nsValue.substring(with: NSRange(location: safeLocation, length: safeLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !substring.isEmpty {
                    return substring
                }
            }
        }

        return nil
    }

    private func copyStringForRange(
        _ element: AXUIElement,
        range: CFRange,
        loggingMode: LoggingMode
    ) -> String? {
        var cfRange = range
        guard let axValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axValue,
            &result
        )
        guard error == .success else {
            log(
                "AX string-for-range unavailable, error=\(error.rawValue)",
                mode: loggingMode,
                minimumMode: .verbose
            )
            return nil
        }

        return result as? String
    }

    private func copyAXElementAttribute(
        _ element: AXUIElement,
        attribute: CFString,
        loggingMode: LoggingMode
    ) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            log("AX copy attribute failed for \(attribute) with error=\(error.rawValue)", mode: loggingMode, minimumMode: .verbose)
            return nil
        }

        guard let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            log("AX attribute \(attribute) returned a non-AXUIElement value.", mode: loggingMode, minimumMode: .verbose)
            return nil
        }

        return (value as! AXUIElement)
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
