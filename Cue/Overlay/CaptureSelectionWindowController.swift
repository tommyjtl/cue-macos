import AppKit
import CoreGraphics
import Foundation

@MainActor
final class CaptureSelectionWindowController: NSObject {
    private enum EscapeCancelConfig {
        static let doubleTapInterval: TimeInterval = 0.35
        static let duplicateEventTolerance: TimeInterval = 0.001
    }

    private enum EscapeHandlingResult {
        case ignoredDuplicate
        case consumeOnly
        case cancel

        var consumesEvent: Bool {
            switch self {
            case .ignoredDuplicate:
                false
            case .consumeOnly, .cancel:
                true
            }
        }
    }

    private var continuation: CheckedContinuation<ScreenCaptureSelection, Error>?
    private var overlayWindows: [SelectionOverlayPanel] = []
    private var isCompleting = false
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var previouslyActiveApplication: NSRunningApplication?
    private var pendingEscapeTapAt: TimeInterval?
    private var lastHandledEscapeEventTimestamp: TimeInterval?

    func selectRect() async throws -> ScreenCaptureSelection {
        guard continuation == nil else {
            throw CaptureError.captureAlreadyInProgress
        }

        guard let target = ScreenLocator.target(containing: NSEvent.mouseLocation) else {
            throw CaptureError.noDisplaysAvailable
        }

        isCompleting = false
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        pendingEscapeTapAt = nil
        lastHandledEscapeEventTimestamp = nil
        buildOverlayWindows(for: target)
        installEscapeMonitorsIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            showOverlayWindows()
        }
    }

    private func buildOverlayWindows(for target: OverlayTarget) {
        let window = SelectionOverlayPanel(
            contentRect: target.displayFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false,
            screen: target.screen
        )
        window.setFrame(target.displayFrame, display: false)

        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.level = .screenSaver
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false

        let selectionView = SelectionOverlayView(frame: NSRect(origin: .zero, size: target.displayFrame.size))
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onEscapeKey = { [weak self] timestamp in
            self?.handleEscapeKeyEvent(timestamp: timestamp).consumesEvent ?? false
        }
        selectionView.onSelectionFinished = { [weak self, weak window] selection in
            guard let self else { return }

            guard let selection, let window else {
                // No region dragged — treat a bare click as a full-screen capture of this display.
                self.finish(
                    with: ScreenCaptureSelection(
                        rect: target.displayFrame,
                        displayID: target.displayID
                    )
                )
                return
            }

            self.finish(
                with: ScreenCaptureSelection(
                    rect: window.convertToScreen(selection),
                    displayID: target.displayID
                )
            )
        }

        window.contentView = selectionView
        window.initialFirstResponder = selectionView
        overlayWindows = [window]
    }

    private func showOverlayWindows() {
        let mouseLocation = NSEvent.mouseLocation
        let keyWindowIndex = overlayWindows.firstIndex(where: { window in
            window.frame.contains(mouseLocation)
        }) ?? 0

        for (index, window) in overlayWindows.enumerated() {
            if index == keyWindowIndex {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }

    private func finish(with selection: ScreenCaptureSelection) {
        guard !isCompleting else { return }
        isCompleting = true
        teardown()
        continuation?.resume(returning: selection)
        continuation = nil
    }

    private func cancel() {
        guard !isCompleting else { return }
        isCompleting = true
        teardown()
        continuation?.resume(throwing: CaptureError.selectionCancelled)
        continuation = nil
    }

    private func teardown() {
        removeEscapeMonitors()
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        pendingEscapeTapAt = nil
        lastHandledEscapeEventTimestamp = nil

        if let previouslyActiveApplication,
           previouslyActiveApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previouslyActiveApplication.activate(options: [])
        }

        previouslyActiveApplication = nil
    }

    private func installEscapeMonitorsIfNeeded() {
        guard localEscapeMonitor == nil, globalEscapeMonitor == nil else {
            return
        }

        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.continuation != nil, event.keyCode == 53 else { return event }
            switch self.handleEscapeKeyEvent(timestamp: event.timestamp) {
            case .ignoredDuplicate:
                return event
            case .consumeOnly, .cancel:
                return nil
            }
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard self.continuation != nil, event.keyCode == 53 else { return }

            if case .cancel = self.handleEscapeKeyEvent(timestamp: event.timestamp) {
                Task { @MainActor in
                    self.cancel()
                }
            }
        }
    }

    private func handleEscapeKeyEvent(timestamp: TimeInterval) -> EscapeHandlingResult {
        if let lastHandledEscapeEventTimestamp,
           abs(timestamp - lastHandledEscapeEventTimestamp) < EscapeCancelConfig.duplicateEventTolerance {
            return .ignoredDuplicate
        }

        lastHandledEscapeEventTimestamp = timestamp

        if let pendingEscapeTapAt,
           timestamp - pendingEscapeTapAt <= EscapeCancelConfig.doubleTapInterval {
            self.pendingEscapeTapAt = nil
            cancel()
            return .cancel
        }

        pendingEscapeTapAt = timestamp
        return .consumeOnly
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }

        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }
}

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    var onEscapeKey: ((TimeInterval) -> Bool)?
    var onSelectionFinished: ((CGRect?) -> Void)?

    private var currentPoint: NSPoint?
    private var startPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)

        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let selection = normalizedSelectionRect
        onSelectionFinished?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if onEscapeKey?(event.timestamp) == true {
                return
            }

            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dimPath = NSBezierPath(rect: bounds)
        if let selection = normalizedSelectionRect {
            dimPath.append(NSBezierPath(rect: selection))
            dimPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.22).setFill()
        dimPath.fill()

        if let selection = normalizedSelectionRect {
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
    }

    private var normalizedSelectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )

        guard rect.width > 2, rect.height > 2 else {
            return nil
        }

        return rect
    }
}