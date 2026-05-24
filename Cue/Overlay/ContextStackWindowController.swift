import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ContextStackWindowController: NSWindowController {
    private enum Layout {
        static let chatMinimumWidth: CGFloat = 360
        static let stackPanelSide: CGFloat = 280
        static let cursorOffset: CGFloat = 0
        static let screenEdgeInset: CGFloat = 12
    }

    private enum MotionMode {
        case normal
        case interacting
    }

    private let onClear: () -> Void
    private let onAppDeactivate: () -> Void
    private let isCaptureInProgress: () -> Bool
    private let onCancelSend: () -> Void
    private let onSendDraft: (String) -> Void
    private let onLoadMostRecent: () -> Void
    private let onSetWebSearchEnabled: (Bool) -> Void
    private let onRemoveContextItem: (ContextPreviewItem) -> Void
    private let panel: ContextStackPanel
    private let hostingView: NSHostingView<ContextStackView>
    private let viewModel: ContextPanelViewModel
    private var displayLink: CADisplayLink?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var cursorEnteredPanelAt: CFTimeInterval?

    init(onClear: @escaping () -> Void, onAppDeactivate: @escaping () -> Void, isCaptureInProgress: @escaping () -> Bool, onCancelSend: @escaping () -> Void, onSendDraft: @escaping (String) -> Void, onLoadMostRecent: @escaping () -> Void, onSetWebSearchEnabled: @escaping (Bool) -> Void, onRemoveContextItem: @escaping (ContextPreviewItem) -> Void) {
        self.onClear = onClear
        self.onAppDeactivate = onAppDeactivate
        self.isCaptureInProgress = isCaptureInProgress
        self.onCancelSend = onCancelSend
        self.onSendDraft = onSendDraft
        self.onLoadMostRecent = onLoadMostRecent
        self.onSetWebSearchEnabled = onSetWebSearchEnabled
        self.onRemoveContextItem = onRemoveContextItem
        let viewModel = ContextPanelViewModel()
        self.viewModel = viewModel
        let initialView = ContextStackView(model: viewModel, onClear: onClear, onCloseChat: {}, onSend: {}, onCancelSend: {}, onLoadMostRecent: {}, onSetWebSearchEnabled: { _ in }, onRemoveContextItem: { _ in })
        hostingView = NSHostingView(rootView: initialView)

        panel = ContextStackPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hostingView

        super.init(window: panel)
        installApplicationLifecycleObserver()
        refreshRootView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(screenshots: [CapturedScreenshot], selectedTextContexts: [SelectedTextManager.SelectionSnapshot], browserPageContexts: [BrowserPageContext], near point: NSPoint) {
        guard !screenshots.isEmpty || !selectedTextContexts.isEmpty || !browserPageContexts.isEmpty else {
            hide()
            return
        }

        updateContext(screenshots: screenshots, selectedTextContexts: selectedTextContexts, browserPageContexts: browserPageContexts)
        viewModel.mode = .stack
        cursorEnteredPanelAt = nil
        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, near: point))
        panel.makeKeyAndOrderFront(nil)
        startFollowingCursor()
    }

    func showChat(screenshots: [CapturedScreenshot], selectedTextContexts: [SelectedTextManager.SelectionSnapshot], browserPageContexts: [BrowserPageContext], near point: NSPoint) {
        guard !screenshots.isEmpty || !selectedTextContexts.isEmpty || !browserPageContexts.isEmpty || !viewModel.messages.isEmpty else {
            return
        }

        viewModel.screenshots = screenshots
        viewModel.selectedTextContexts = selectedTextContexts
        viewModel.browserPageContexts = browserPageContexts
        viewModel.mode = .chat
        refreshPanelSize()
        cursorEnteredPanelAt = nil

        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, near: point))

        panel.makeKeyAndOrderFront(nil)
        requestComposerFocus()
        startFollowingCursor()
    }

    func updateContext(screenshots: [CapturedScreenshot], selectedTextContexts: [SelectedTextManager.SelectionSnapshot], browserPageContexts: [BrowserPageContext]) {
        viewModel.screenshots = screenshots
        viewModel.selectedTextContexts = selectedTextContexts
        viewModel.browserPageContexts = browserPageContexts
        refreshPanelSize()
    }

    func updateConversation(messages: [ConversationMessageDTO], isSending: Bool, canCancelSend: Bool, providerDisplayName: String, hasSavedConversations: Bool, supportsWebSearch: Bool, isWebSearchEnabled: Bool) {
        viewModel.messages = messages
        viewModel.isSending = isSending
        viewModel.canCancelSend = canCancelSend
        viewModel.providerDisplayName = providerDisplayName
        viewModel.hasSavedConversations = hasSavedConversations
        viewModel.supportsWebSearch = supportsWebSearch
        viewModel.isWebSearchEnabled = isWebSearchEnabled
        refreshPanelSize()
    }

    func hide() {
        stopFollowingCursor()
        cursorEnteredPanelAt = nil
        viewModel.mode = .stack
        viewModel.draftMessage = "" 
        viewModel.messages = []
        viewModel.isSending = false
        viewModel.canCancelSend = false
        viewModel.providerDisplayName = ""
        viewModel.supportsWebSearch = false
        viewModel.isWebSearchEnabled = false
        viewModel.screenshots = []
        viewModel.selectedTextContexts = []
        viewModel.browserPageContexts = []
        panel.orderOut(nil)
    }

    private func startFollowingCursor() {
        guard displayLink == nil else {
            return
        }

        installEscapeMonitorsIfNeeded()

        let newDisplayLink = panel.displayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
        newDisplayLink.add(to: .main, forMode: .common)

        displayLink = newDisplayLink
    }

    private func stopFollowingCursor() {
        if let displayLink {
            displayLink.invalidate()
            self.displayLink = nil
        }
        removeEscapeMonitors()
    }

    private func installApplicationLifecycleObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActiveNotification(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc
    private func handleDisplayLinkTick(_ sender: CADisplayLink) {
        updatePositionIfNeeded()
    }

    @objc
    private func handleAppDidResignActiveNotification(_ notification: Notification) {
        // Keep the overlay visible across app switches; chat should close only by explicit user action.
    }

    private func updatePositionIfNeeded() {
        guard panel.isVisible else {
            stopFollowingCursor()
            return
        }

        guard viewModel.mode != .chat else {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let mouseLocation = NSEvent.mouseLocation

        let motionMode = resolveMotionMode(cursorLocation: mouseLocation, now: now)
        // Temporarily keep following even while the cursor is over the panel.
        // guard motionMode != .interacting else { return }

        let targetOrigin = clampedOrigin(for: panel.frame.size, near: mouseLocation)
        guard abs(panel.frame.origin.x - targetOrigin.x) > 1 || abs(panel.frame.origin.y - targetOrigin.y) > 1 else {
            return
        }

        let nextOrigin = interpolatedOrigin(from: panel.frame.origin, toward: targetOrigin, mode: motionMode)
        panel.setFrameOrigin(nextOrigin)
    }

    private func resolveMotionMode(cursorLocation: NSPoint, now: CFTimeInterval) -> MotionMode {
        if panel.frame.contains(cursorLocation) {
            if cursorEnteredPanelAt == nil {
                cursorEnteredPanelAt = now
            }

            if let cursorEnteredPanelAt, now - cursorEnteredPanelAt > 0.08 {
                return .interacting
            }
        } else {
            cursorEnteredPanelAt = nil
        }

        return .normal
    }

    private func interpolatedOrigin(from current: NSPoint, toward target: NSPoint, mode: MotionMode) -> NSPoint {
        let deltaX = target.x - current.x
        let deltaY = target.y - current.y

        let smoothing: CGFloat
        switch mode {
        case .normal:
            smoothing = 0.15
        case .interacting:
            smoothing = 0.05
        }

        if abs(deltaX) < 2, abs(deltaY) < 2 {
            return target
        }

        return NSPoint(
            x: current.x + deltaX * smoothing,
            y: current.y + deltaY * smoothing
        )
    }

    private func installEscapeMonitorsIfNeeded() {
        guard localEscapeMonitor == nil,
              globalEscapeMonitor == nil,
              localMouseDownMonitor == nil,
              globalMouseDownMonitor == nil else {
            return
        }

        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isVisible, event.keyCode == 53 else { return event }
            guard !self.isCaptureInProgress() else { return event }

            if self.viewModel.mode == .chat {
                self.exitChatMode()
                return nil
            }

            self.onClear()
            return nil
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard self.panel.isVisible, event.keyCode == 53 else { return }
            guard !self.isCaptureInProgress() else { return }

            self.onClear()
        }

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleMouseDown()
            return event
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.handleMouseDown()
        }
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

        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }

        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
    }

    private func clampedOrigin(for size: NSSize, near point: NSPoint) -> NSPoint {
        let placementFrame = ScreenLocator.target(containing: point)?.placementFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        // Prefer placing to the right of the cursor; flip to the left if it would overflow the right edge.
        let rightOriginX = point.x + Layout.cursorOffset
        let leftOriginX = point.x - size.width - Layout.cursorOffset
        let fitsOnRight = rightOriginX + size.width <= placementFrame.maxX - Layout.screenEdgeInset

        var origin = NSPoint(
            x: fitsOnRight ? rightOriginX : leftOriginX,
            y: point.y - size.height - Layout.cursorOffset
        )

        // Vertical: if panel goes below screen, place above cursor.
        if origin.y < placementFrame.minY {
            origin.y = min(
                point.y + Layout.cursorOffset,
                placementFrame.maxY - size.height - Layout.screenEdgeInset
            )
        }

        // Final clamp to keep panel fully within the screen on all edges.
        origin.x = max(origin.x, placementFrame.minX + Layout.screenEdgeInset)
        origin.y = min(
            max(origin.y, placementFrame.minY + Layout.screenEdgeInset),
            placementFrame.maxY - size.height - Layout.screenEdgeInset
        )

        return origin
    }
    private func refreshRootView() {
        hostingView.rootView = ContextStackView(
            model: viewModel,
            onClear: onClear,
            onCloseChat: { [weak self] in
                self?.exitChatMode()
            },
            onSend: { [weak self] in
                self?.sendCurrentDraft()
            },
            onCancelSend: { [weak self] in
                self?.onCancelSend()
            },
            onLoadMostRecent: { [weak self] in
                self?.onLoadMostRecent()
            },
            onSetWebSearchEnabled: { [weak self] isEnabled in
                self?.onSetWebSearchEnabled(isEnabled)
            },
            onRemoveContextItem: { [weak self] item in
                self?.onRemoveContextItem(item)
            }
        )
    }

    private func refreshPanelSize() {
        hostingView.layoutSubtreeIfNeeded()
        let frame = panel.frame
        let size: NSSize

        if viewModel.mode == .chat {
            let fittingSize = hostingView.fittingSize
            let screenHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            let maxPanelHeight = screenHeight * 0.65
            size = NSSize(
                width: max(Layout.chatMinimumWidth, fittingSize.width),
                height: min(max(120, fittingSize.height), maxPanelHeight)
            )
        } else {
            size = NSSize(width: Layout.stackPanelSide, height: Layout.stackPanelSide)
        }

        // Anchor to the top edge so the panel expands downward when growing.
        let origin = viewModel.mode == .chat
            ? NSPoint(x: frame.origin.x, y: frame.maxY - size.height)
            : frame.origin

        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true
        )
    }

    private func exitChatMode() {
        guard viewModel.mode == .chat else {
            return
        }

        if viewModel.isSending {
            onCancelSend()
        }

        viewModel.mode = .stack
        viewModel.draftMessage = ""
        refreshPanelSize()
    }

    private func sendCurrentDraft() {
        let draft = viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            return
        }

        viewModel.draftMessage = ""
        onSendDraft(draft)
    }

    private func handleMouseDown() {
        guard panel.isVisible, viewModel.mode == .chat else {
            return
        }

        if !panel.frame.contains(NSEvent.mouseLocation) {
            exitChatMode()
        }
    }

    private func requestComposerFocus() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.composerFocusRequestID = UUID()
        }
    }
}

private final class ContextStackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
