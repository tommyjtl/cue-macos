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
            let role = AccessibilityClient.copyStringAttribute(
                element,
                attribute: kAXRoleAttribute as CFString
            )
            let subrole = AccessibilityClient.copyStringAttribute(
                element,
                attribute: kAXSubroleAttribute as CFString
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
        let role = AccessibilityClient.copyStringAttribute(
            primaryElement,
            attribute: kAXRoleAttribute as CFString
        )
        let subrole = AccessibilityClient.copyStringAttribute(
            primaryElement,
            attribute: kAXSubroleAttribute as CFString
        )

        if let selectedRange = AccessibilityClient.copyCFRangeAttribute(
            primaryElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ), selectedRange.length > 0 {
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

        appendRoot(AccessibilityClient.copyElementAttribute(
            systemWideElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ))

        if let pid = frontmostApplication?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            appendRoot(AccessibilityClient.copyElementAttribute(
                appElement,
                attribute: kAXFocusedUIElementAttribute as CFString
            ))

            if let focusedWindow = AccessibilityClient.copyElementAttribute(
                appElement,
                attribute: kAXFocusedWindowAttribute as CFString
            ) {
                appendRoot(AccessibilityClient.copyElementAttribute(
                    focusedWindow,
                    attribute: kAXFocusedUIElementAttribute as CFString
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
                current = AccessibilityClient.copyElementAttribute(
                    element,
                    attribute: kAXParentAttribute as CFString
                )
                depth += 1
            }
        }

        return candidates
    }

    private func selectedText(from element: AXUIElement, loggingMode: LoggingMode) -> String? {
        if let direct = AccessibilityClient.copyStringAttribute(
            element,
            attribute: kAXSelectedTextAttribute as CFString
        ) {
            let trimmedText = direct.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                return trimmedText
            }
        }

        guard let selectedRange = AccessibilityClient.copyCFRangeAttribute(
            element,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ), selectedRange.length > 0 else {
            return nil
        }

        if let rangedText = AccessibilityClient.copyParameterizedString(
            element,
            attribute: kAXStringForRangeParameterizedAttribute as CFString,
            range: selectedRange
        ) {
            let trimmedText = rangedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                return trimmedText
            }
        }

        if let valueText = AccessibilityClient.copyStringAttribute(
            element,
            attribute: kAXValueAttribute as CFString
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
