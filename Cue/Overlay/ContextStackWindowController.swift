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
    private let onPresentationChange: () -> Void
    private let panel: ContextStackPanel
    private let hostingView: NSHostingView<ContextStackView>
    private let viewModel: ContextPanelViewModel
    private var displayLink: CADisplayLink?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var cursorEnteredPanelAt: CFTimeInterval?
    private var lastEscapeRollbackAt: CFTimeInterval?

    init(onClear: @escaping () -> Void, onAppDeactivate: @escaping () -> Void, isCaptureInProgress: @escaping () -> Bool, onCancelSend: @escaping () -> Void, onSendDraft: @escaping (String) -> Void, onLoadMostRecent: @escaping () -> Void, onSetWebSearchEnabled: @escaping (Bool) -> Void, onRemoveContextItem: @escaping (ContextPreviewItem) -> Void, onPresentationChange: @escaping () -> Void) {
        self.onClear = onClear
        self.onAppDeactivate = onAppDeactivate
        self.isCaptureInProgress = isCaptureInProgress
        self.onCancelSend = onCancelSend
        self.onSendDraft = onSendDraft
        self.onLoadMostRecent = onLoadMostRecent
        self.onSetWebSearchEnabled = onSetWebSearchEnabled
        self.onRemoveContextItem = onRemoveContextItem
        self.onPresentationChange = onPresentationChange
        let viewModel = ContextPanelViewModel()
        self.viewModel = viewModel
        let initialView = ContextStackView(model: viewModel, onClear: onClear, onCloseChat: {}, onSend: {}, onCancelSend: {}, onLoadMostRecent: {}, onSetWebSearchEnabled: { _ in }, onRemoveContextItem: { _ in }, onEscape: {})
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
            self?.handleEscapeRollback() ?? false
        }
        setPanelInteractionMode(for: .stack)
        installApplicationLifecycleObserver()
        refreshRootView()
        installEscapeMonitorsIfNeeded()
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

    var isInChatMode: Bool {
        viewModel.mode == .chat
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
        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, near: point))
        presentStackPanelWithoutActivatingApp(revertingTo: previousApp)
        startFollowingCursor()
        notifyPresentationChange()
    }

    func showChat(screenshots: [CapturedScreenshot], selectedTextContexts: [AttachedTextContext], browserPageContexts: [BrowserPageContext], near point: NSPoint) {
        guard !screenshots.isEmpty || !selectedTextContexts.isEmpty || !browserPageContexts.isEmpty || !viewModel.messages.isEmpty else {
            return
        }

        viewModel.screenshots = screenshots
        viewModel.selectedTextContexts = selectedTextContexts
        viewModel.browserPageContexts = browserPageContexts
        viewModel.mode = .chat
        setPanelInteractionMode(for: .chat)
        refreshPanelSize()
        cursorEnteredPanelAt = nil

        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, near: point))

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        requestComposerFocus()
        startFollowingCursor()
        SoundEffectPlayer.play(.chatOpened)
        notifyPresentationChange()
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
        setPanelInteractionMode(for: .stack)
        panel.orderOut(nil)
        notifyPresentationChange()
    }

    private func startFollowingCursor() {
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
        installLocalEventMonitorsIfNeeded()
        installGlobalEventMonitorsIfNeeded()
    }

    func refreshAccessibilityDependentGlobalMonitors() {
        removeGlobalEventMonitors()
        installGlobalEventMonitorsIfNeeded()
    }

    private func installLocalEventMonitorsIfNeeded() {
        if localEscapeMonitor == nil {
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.panel.isVisible else { return event }

                if let handled = self.handleChatComposerKeyEquivalent(event) {
                    return handled
                }

                guard self.isEscapeKeyEvent(event) else { return event }

                return self.handleEscapeRollback() ? nil : event
            }
        }

        if localMouseDownMonitor == nil {
            localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                self?.handleMouseDown()
                return event
            }
        }
    }

    private func installGlobalEventMonitorsIfNeeded() {
        if globalEscapeMonitor == nil {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Self.isEscapeKeyEvent(event) else { return }
                Task { @MainActor in
                    guard let self, self.panel.isVisible else { return }
                    self.handleEscapeRollback()
                }
            }

            if globalEscapeMonitor == nil {
                print("[ContextStackWindowController] Global Escape monitor unavailable — grant Accessibility to dismiss the overlay from other apps")
            }
        }

        if globalMouseDownMonitor == nil {
            globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.handleMouseDown()
            }
        }
    }

    private func removeGlobalEventMonitors() {
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }

        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }

        removeGlobalEventMonitors()

        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
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
            },
            onEscape: { [weak self] in
                _ = self?.handleEscapeRollback()
            }
        )
    }

    /// Rolls back one overlay level: chat → context stack → dismissed.
    @discardableResult
    func handleEscapeRollback() -> Bool {
        guard panel.isVisible else { return false }
        guard !isCaptureInProgress() else { return false }

        let now = CFAbsoluteTimeGetCurrent()
        if let lastEscapeRollbackAt, now - lastEscapeRollbackAt < 0.15 {
            return true
        }
        lastEscapeRollbackAt = now

        switch viewModel.mode {
        case .chat:
            exitChatMode()
        case .stack:
            onClear()
        }

        notifyPresentationChange()
        return true
    }

    nonisolated static func isEscapeKeyEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 53
            && event.modifierFlags.intersection(CaptureShortcut.modifierFlagsMask).isEmpty
    }

    private func isEscapeKeyEvent(_ event: NSEvent) -> Bool {
        Self.isEscapeKeyEvent(event)
    }

    private func notifyPresentationChange() {
        onPresentationChange()
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

        let nextFrame = NSRect(origin: origin, size: size)
        let sizeChanged = abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1
        guard sizeChanged || panel.frame.origin != origin else {
            return
        }

        panel.setFrame(nextFrame, display: true)
    }

    private func setPanelInteractionMode(for mode: ContextPanelViewModel.Mode) {
        switch mode {
        case .chat:
            panel.styleMask.remove(.nonactivatingPanel)
            panel.becomesKeyOnlyIfNeeded = false
            panel.requiresInteractiveKeyboardInput = true
        case .stack:
            if !panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.insert(.nonactivatingPanel)
            }
            panel.becomesKeyOnlyIfNeeded = true
            panel.requiresInteractiveKeyboardInput = false
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

        viewModel.mode = .stack
        viewModel.draftMessage = ""
        setPanelInteractionMode(for: .stack)
        refreshPanelSize()
        notifyPresentationChange()
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

    private func handleChatComposerKeyEquivalent(_ event: NSEvent) -> NSEvent? {
        guard viewModel.mode == .chat, panel.isKeyWindow else {
            return event
        }

        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "a" else {
            return event
        }

        if let textView = panel.firstResponder as? NSTextView {
            textView.selectAll(nil)
            return nil
        }

        if let textField = panel.firstResponder as? NSTextField {
            textField.selectText(nil)
            return nil
        }

        return event
    }

    private func resignComposerInputFocus() {
        if let textField = composerTextField() ?? findComposerTextField(in: hostingView),
           textField.currentEditor() != nil {
            textField.abortEditing()
        }

        panel.makeFirstResponder(nil)
    }

    private func findComposerTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }

        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }

        for subview in view.subviews {
            if let textField = findComposerTextField(in: subview) {
                return textField
            }
        }

        return nil
    }

    private func composerTextField() -> NSTextField? {
        if let textField = panel.firstResponder as? NSTextField {
            return textField
        }

        if let textView = panel.firstResponder as? NSTextView,
           textView.isFieldEditor,
           let textField = textView.delegate as? NSTextField {
            return textField
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

        return super.performKeyEquivalent(with: event)
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
