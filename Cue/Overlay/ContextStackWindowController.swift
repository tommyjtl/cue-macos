import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ContextStackWindowController: NSWindowController {
    private enum Layout {
        static let chatMinimumWidth: CGFloat = 360
        static let stackPanelSide: CGFloat = 280
    }

    private enum MotionMode {
        case normal
        case interacting
    }

    private let onClear: () -> Void
    private let isCaptureInProgress: () -> Bool
    private let onCancelSend: () -> Void
    private let onSendDraft: (String) -> Void
    private let onLoadMostRecent: () -> Void
    private let onSetWebSearchEnabled: (Bool) -> Void
    private let onRemoveContextItem: (ContextPreviewItem) -> Void
    private let onDeleteMessage: (UUID) -> Void
    private let onPresentationChange: () -> Void
    private let panel: ContextStackPanel
    private let hostingView: NSHostingView<ContextStackView>
    private let viewModel: ContextPanelViewModel
    private var dismissChatShortcut: DismissChatShortcut
    /// Read from the global keyDown monitor callback (nonisolated context).
    private nonisolated(unsafe) var globalMonitorDismissShortcut: DismissChatShortcut
    /// Read from the global keyDown monitor callback (nonisolated context).
    private nonisolated(unsafe) var globalMonitorPanelIsVisible = false
    private var dismissShortcutPressTracker = RepeatedKeyPressTracker()
    private var displayLink: CADisplayLink?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var cursorEnteredPanelAt: CFTimeInterval?
    private var lastEscapeRollbackAt: CFTimeInterval?
    private var placementAnchor: NSPoint?
    private var chatPanelManuallyPositioned = false
    private var isUserDraggingChatPanel = false
    private var panelDragObserver: NSObjectProtocol?

    init(
        dismissChatShortcut: DismissChatShortcut? = nil,
        onClear: @escaping () -> Void,
        isCaptureInProgress: @escaping () -> Bool,
        onCancelSend: @escaping () -> Void,
        onSendDraft: @escaping (String) -> Void,
        onLoadMostRecent: @escaping () -> Void,
        onSetWebSearchEnabled: @escaping (Bool) -> Void,
        onRemoveContextItem: @escaping (ContextPreviewItem) -> Void,
        onDeleteMessage: @escaping (UUID) -> Void,
        onPresentationChange: @escaping () -> Void
    ) {
        let normalizedDismissChatShortcut = (dismissChatShortcut ?? DismissChatShortcut.defaultValue).normalized
        self.dismissChatShortcut = normalizedDismissChatShortcut
        self.globalMonitorDismissShortcut = normalizedDismissChatShortcut
        self.onClear = onClear
        self.isCaptureInProgress = isCaptureInProgress
        self.onCancelSend = onCancelSend
        self.onSendDraft = onSendDraft
        self.onLoadMostRecent = onLoadMostRecent
        self.onSetWebSearchEnabled = onSetWebSearchEnabled
        self.onRemoveContextItem = onRemoveContextItem
        self.onDeleteMessage = onDeleteMessage
        self.onPresentationChange = onPresentationChange
        let viewModel = ContextPanelViewModel()
        self.viewModel = viewModel
        let initialView = ContextStackView(model: viewModel, onClear: onClear, onCloseChat: {}, onSend: {}, onCancelSend: {}, onLoadMostRecent: {}, onSetWebSearchEnabled: { _ in }, onRemoveContextItem: { _ in }, onDeleteMessage: { _ in }, onEscape: {})
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
        panel.onEscapeKey = { [weak self] in
            guard let self, self.viewModel.mode == .stack else { return false }
            return self.handleEscapeRollback()
        }
        setPanelInteractionMode(for: .stack)
        installPanelDragObserver()
        refreshRootView()
        installEscapeMonitorsIfNeeded()
    }

    deinit {
        if let panelDragObserver {
            NotificationCenter.default.removeObserver(panelDragObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var isInChatMode: Bool {
        viewModel.mode == .chat
    }

    var isComposerInputFocused: Bool {
        guard viewModel.mode == .chat, panel.isKeyWindow else { return false }
        return composerInputView() != nil
    }

    func show(screenshots: [CapturedScreenshot], selectedTextContexts: [AttachedTextContext], browserPageContexts: [BrowserPageContext], near point: NSPoint) {
        let previousApp = NSWorkspace.shared.frontmostApplication

        guard !screenshots.isEmpty || !selectedTextContexts.isEmpty || !browserPageContexts.isEmpty else {
            hide()
            return
        }

        updateContext(screenshots: screenshots, selectedTextContexts: selectedTextContexts, browserPageContexts: browserPageContexts)
        viewModel.mode = .stack
        setPanelInteractionMode(for: .stack)
        cursorEnteredPanelAt = nil
        applyPlacement(anchor: point)
        presentStackPanelWithoutActivatingApp(revertingTo: previousApp)
        globalMonitorPanelIsVisible = true
        startFollowingCursor()
        notifyPresentationChange()
    }

    func relayout() {
        applyPlacement()
    }

    func showChat(screenshots: [CapturedScreenshot], selectedTextContexts: [AttachedTextContext], browserPageContexts: [BrowserPageContext], near point: NSPoint) {
        viewModel.screenshots = screenshots
        viewModel.selectedTextContexts = selectedTextContexts
        viewModel.browserPageContexts = browserPageContexts
        viewModel.mode = .chat
        resetDismissShortcutPressTracking()
        setPanelInteractionMode(for: .chat)
        cursorEnteredPanelAt = nil
        stopFollowingCursor()
        applyPlacement(anchor: point)

        activateChatComposerFocus()
        globalMonitorPanelIsVisible = true
        SoundEffectPlayer.play(.chatOpened)
        notifyPresentationChange()
    }

    func focusChatComposer() {
        guard viewModel.mode == .chat, panel.isVisible else { return }
        activateChatComposerFocus()
    }

    private func activateChatComposerFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        requestComposerFocus()
    }

    private func presentStackPanelWithoutActivatingApp(revertingTo previousApp: NSRunningApplication?) {
        panel.orderFront(nil)
        restoreFrontmostApplicationIfNeeded(previousApp)
    }

    private func restoreFrontmostApplicationIfNeeded(_ app: NSRunningApplication?) {
        guard let app else { return }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        DispatchQueue.main.async {
            app.activate(options: [])
        }
    }

    func updateContext(screenshots: [CapturedScreenshot], selectedTextContexts: [AttachedTextContext], browserPageContexts: [BrowserPageContext]) {
        viewModel.screenshots = screenshots
        viewModel.selectedTextContexts = selectedTextContexts
        viewModel.browserPageContexts = browserPageContexts
        if panel.isVisible {
            applyPlacement()
        }
    }

    func updateConversation(
        messages: [ConversationMessageDTO],
        isSending: Bool,
        canCancelSend: Bool,
        inFlightActivity: ComposerInFlightActivity,
        conversationProvider: ConversationProvider,
        providerDisplayName: String,
        hasSavedConversations: Bool,
        supportsWebSearch: Bool,
        isWebSearchEnabled: Bool
    ) {
        viewModel.messages = messages
        viewModel.isSending = isSending
        viewModel.canCancelSend = canCancelSend
        viewModel.inFlightActivity = inFlightActivity
        viewModel.conversationProvider = conversationProvider
        viewModel.providerDisplayName = providerDisplayName
        viewModel.hasSavedConversations = hasSavedConversations
        viewModel.supportsWebSearch = supportsWebSearch
        viewModel.isWebSearchEnabled = isWebSearchEnabled
        if panel.isVisible {
            applyPlacement()
            if viewModel.mode == .chat {
                scheduleDeferredRelayout()
            }
        }
    }

    func hide() {
        stopFollowingCursor()
        cursorEnteredPanelAt = nil
        placementAnchor = nil
        chatPanelManuallyPositioned = false
        isUserDraggingChatPanel = false
        viewModel.mode = .stack
        viewModel.draftMessage = "" 
        viewModel.messages = []
        viewModel.isSending = false
        viewModel.canCancelSend = false
        viewModel.inFlightActivity = .none
        viewModel.conversationProvider = .ollama
        viewModel.providerDisplayName = ""
        viewModel.supportsWebSearch = false
        viewModel.isWebSearchEnabled = false
        viewModel.screenshots = []
        viewModel.selectedTextContexts = []
        viewModel.browserPageContexts = []
        setPanelInteractionMode(for: .stack)
        panel.orderOut(nil)
        globalMonitorPanelIsVisible = false
        notifyPresentationChange()
    }

    private func startFollowingCursor() {
        guard viewModel.mode == .stack else {
            return
        }

        guard displayLink == nil else {
            return
        }

        let newDisplayLink = panel.displayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
        newDisplayLink.add(to: .main, forMode: .common)

        displayLink = newDisplayLink
    }

    private func stopFollowingCursor() {
        if let displayLink {
            displayLink.invalidate()
            self.displayLink = nil
        }
    }

    @objc
    private func handleDisplayLinkTick(_ sender: CADisplayLink) {
        updatePositionIfNeeded()
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
        placementAnchor = mouseLocation

        let motionMode = resolveMotionMode(cursorLocation: mouseLocation, now: now)
        let targetOrigin = OverlayPlacement.clampedOrigin(for: panel.frame.size, near: mouseLocation)
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
        installLocalEventMonitorsIfNeeded()
        installGlobalEventMonitorsIfNeeded()
    }

    func refreshAccessibilityDependentGlobalMonitors() {
        removeGlobalEventMonitors()
        installGlobalEventMonitorsIfNeeded()
    }

    func updateDismissChatShortcut(_ shortcut: DismissChatShortcut) {
        let normalizedShortcut = shortcut.normalized
        dismissChatShortcut = normalizedShortcut
        globalMonitorDismissShortcut = normalizedShortcut
        resetDismissShortcutPressTracking()
    }

    private func installLocalEventMonitorsIfNeeded() {
        if localEscapeMonitor == nil {
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.panel.isVisible else { return event }

                return self.handleOverlayKeyDown(event) ? nil : event
            }
        }
    }

    private func installGlobalEventMonitorsIfNeeded() {
        if globalEscapeMonitor == nil {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return }
                guard self.globalMonitorPanelIsVisible else { return }
                guard Self.couldBeOverlayDismissKeyDown(event, dismissShortcut: self.globalMonitorDismissShortcut) else {
                    return
                }

                Task { @MainActor in
                    guard self.panel.isVisible else { return }
                    _ = self.handleOverlayKeyDown(event)
                }
            }

            if globalEscapeMonitor == nil {
                print("[ContextStackWindowController] Global shortcut monitor unavailable — grant Accessibility to dismiss chat or the context stack from other apps")
            }
        }
    }

    private func removeGlobalEventMonitors() {
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }

        removeGlobalEventMonitors()
    }

    private func installPanelDragObserver() {
        panelDragObserver = NotificationCenter.default.addObserver(
            forName: .overlayPanelUserDidDrag,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }

                let isDragging = notification.userInfo?[OverlayPanelDragNotification.isDraggingKey] as? Bool ?? false
                if isDragging {
                    self.chatPanelManuallyPositioned = true
                    self.isUserDraggingChatPanel = true
                } else {
                    self.isUserDraggingChatPanel = false
                    if self.viewModel.mode == .chat, self.chatPanelManuallyPositioned {
                        self.scheduleDeferredRelayout()
                    }
                }
            }
        }
    }

    private func scheduleDeferredRelayout() {
        DispatchQueue.main.async { [weak self] in
            self?.applyPlacement()
        }
    }

    private func applyPlacement(anchor: NSPoint? = nil) {
        if let anchor {
            placementAnchor = anchor
            chatPanelManuallyPositioned = false
        }

        hostingView.layoutSubtreeIfNeeded()
        let size = measuredPanelSize()

        let origin: NSPoint
        if viewModel.mode == .chat, chatPanelManuallyPositioned {
            let proposedOrigin = NSPoint(
                x: panel.frame.origin.x,
                y: panel.frame.maxY - size.height
            )
            origin = OverlayPlacement.clampedOriginPreservingUserPosition(
                proposedOrigin: proposedOrigin,
                size: size
            )
        } else {
            guard let placementAnchor else {
                return
            }
            origin = OverlayPlacement.clampedOrigin(for: size, near: placementAnchor)
        }

        let nextFrame = NSRect(origin: origin, size: size)

        guard !framesAreApproximatelyEqual(panel.frame, nextFrame) else {
            return
        }

        if viewModel.mode == .chat, isUserDraggingChatPanel {
            return
        }

        panel.setFrame(nextFrame, display: true)
    }

    private func measuredPanelSize() -> NSSize {
        if viewModel.mode == .chat {
            let fittingSize = hostingView.fittingSize
            let screenHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
            let maxPanelHeight = screenHeight * 0.65
            return NSSize(
                width: max(Layout.chatMinimumWidth, fittingSize.width),
                height: min(max(120, fittingSize.height), maxPanelHeight)
            )
        }

        return NSSize(width: Layout.stackPanelSide, height: Layout.stackPanelSide)
    }

    private func framesAreApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= 1
            && abs(lhs.origin.y - rhs.origin.y) <= 1
            && abs(lhs.size.width - rhs.size.width) <= 1
            && abs(lhs.size.height - rhs.size.height) <= 1
    }

    private func refreshRootView() {
        hostingView.rootView = ContextStackView(
            model: viewModel,
            onClear: onClear,
            onCloseChat: { [weak self] in
                self?.closeChat()
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
            },
            onDeleteMessage: { [weak self] messageID in
                self?.onDeleteMessage(messageID)
            },
            onEscape: {}
        )
    }

    /// Dismisses the context stack when Escape is pressed. Chat closes via the configured dismiss shortcut.
    @discardableResult
    func handleEscapeRollback() -> Bool {
        guard panel.isVisible else { return false }
        guard !isCaptureInProgress() else { return false }
        guard viewModel.mode == .stack else { return false }

        let now = CFAbsoluteTimeGetCurrent()
        if let lastEscapeRollbackAt, now - lastEscapeRollbackAt < 0.15 {
            return true
        }
        lastEscapeRollbackAt = now

        onClear()
        notifyPresentationChange()
        return true
    }

    @discardableResult
    func handleOverlayKeyDown(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        guard !isCaptureInProgress() else { return false }

        switch viewModel.mode {
        case .stack:
            guard isEscapeKeyEvent(event) else { return false }
            return handleEscapeRollback()
        case .chat:
            guard dismissChatShortcut.matches(event) else { return false }
            handleDismissChatShortcutPress()
            return true
        }
    }

    private func handleDismissChatShortcutPress() {
        guard dismissShortcutPressTracker.registerPress(shortcut: dismissChatShortcut) else {
            return
        }

        closeChat()
        notifyPresentationChange()
    }

    private func resetDismissShortcutPressTracking() {
        dismissShortcutPressTracker.reset()
    }

    func closeChat() {
        resetDismissShortcutPressTracking()
        exitChatMode()
    }

    nonisolated static func isEscapeKeyEvent(_ event: NSEvent) -> Bool {
        let modifierFlagsMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return event.keyCode == 53
            && event.modifierFlags.intersection(modifierFlagsMask).isEmpty
    }

    nonisolated static func couldBeOverlayDismissKeyDown(
        _ event: NSEvent,
        dismissShortcut: DismissChatShortcut
    ) -> Bool {
        isEscapeKeyEvent(event) || dismissShortcut.matches(event)
    }

    private func isEscapeKeyEvent(_ event: NSEvent) -> Bool {
        Self.isEscapeKeyEvent(event)
    }

    private func notifyPresentationChange() {
        onPresentationChange()
    }

    private func setPanelInteractionMode(for mode: ContextPanelViewModel.Mode) {
        switch mode {
        case .chat:
            if !panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.insert(.nonactivatingPanel)
            }
            panel.becomesKeyOnlyIfNeeded = false
            panel.requiresInteractiveKeyboardInput = true
            panel.acceptsMouseMovedEvents = true
        case .stack:
            if !panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.insert(.nonactivatingPanel)
            }
            panel.becomesKeyOnlyIfNeeded = true
            panel.requiresInteractiveKeyboardInput = false
            panel.acceptsMouseMovedEvents = false
        }
    }

    private func exitChatMode() {
        guard viewModel.mode == .chat else {
            return
        }

        resignComposerInputFocus()

        if viewModel.isSending {
            onCancelSend()
        }

        viewModel.draftMessage = ""
        viewModel.composerVisibleLineCount = 1

        let hasContext = !viewModel.screenshots.isEmpty
            || !viewModel.selectedTextContexts.isEmpty
            || !viewModel.browserPageContexts.isEmpty

        if hasContext {
            viewModel.mode = .stack
            setPanelInteractionMode(for: .stack)
            applyPlacement()
            startFollowingCursor()
            notifyPresentationChange()
        } else {
            hide()
        }
    }

    private func sendCurrentDraft() {
        let draft = viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            return
        }

        viewModel.draftMessage = ""
        viewModel.composerVisibleLineCount = 1
        onSendDraft(draft)
    }

    private func resignComposerInputFocus() {
        if composerInputView() != nil || findComposerInputView(in: hostingView) != nil {
            panel.makeFirstResponder(nil)
        }
    }

    private func findComposerInputView(in view: NSView?) -> ComposerInputTextView? {
        guard let view else { return nil }

        if let textView = view as? ComposerInputTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findComposerInputView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func composerInputView() -> ComposerInputTextView? {
        if let textView = panel.firstResponder as? ComposerInputTextView {
            return textView
        }

        return nil
    }

    private func requestComposerFocus() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.composerFocusRequestID = UUID()
        }
    }
}

private final class ContextStackPanel: NSPanel {
    var requiresInteractiveKeyboardInput = false
    var onEscapeKey: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if ContextStackWindowController.isEscapeKeyEvent(event), onEscapeKey?() == true {
            return true
        }

        if super.performKeyEquivalent(with: event) {
            return true
        }

        if requiresInteractiveKeyboardInput,
           ComposerEditShortcut.perform(with: event, sender: firstResponder) {
            return true
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        if ContextStackWindowController.isEscapeKeyEvent(event), onEscapeKey?() == true {
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if requiresInteractiveKeyboardInput {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.mouseDown(with: event)
    }
}
