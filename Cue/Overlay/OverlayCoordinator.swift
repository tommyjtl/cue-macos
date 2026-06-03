import AppKit
import Foundation

@MainActor
final class OverlayCoordinator {
    struct Snapshot {
        var screenshots: [CapturedScreenshot] = []
        var selectedTextContexts: [AttachedTextContext] = []
        var browserPageContexts: [BrowserPageContext] = []
        var messages: [ConversationMessageDTO] = []
        var isSending = false
        var canCancelSend = false
        var conversationProvider: ConversationProvider = .ollama
        var providerDisplayName = ""
        var hasSavedConversations = false
        var supportsWebSearch = false
        var isWebSearchEnabled = false
    }

    private let windowController: ContextStackWindowController
    private var snapshot = Snapshot()

    init(
        dismissChatShortcut: DismissChatShortcut? = nil,
        onClear: @escaping () -> Void,
        isCaptureInProgress: @escaping () -> Bool,
        onCancelSend: @escaping () -> Void,
        onSendDraft: @escaping (String) -> Void,
        onLoadMostRecent: @escaping () -> Void,
        onSetWebSearchEnabled: @escaping (Bool) -> Void,
        onRemoveContextItem: @escaping (ContextPreviewItem) -> Void,
        onPresentationChange: @escaping () -> Void
    ) {
        windowController = ContextStackWindowController(
            dismissChatShortcut: dismissChatShortcut,
            onClear: onClear,
            isCaptureInProgress: isCaptureInProgress,
            onCancelSend: onCancelSend,
            onSendDraft: onSendDraft,
            onLoadMostRecent: onLoadMostRecent,
            onSetWebSearchEnabled: onSetWebSearchEnabled,
            onRemoveContextItem: onRemoveContextItem,
            onPresentationChange: onPresentationChange
        )
    }

    var isVisible: Bool {
        windowController.isVisible
    }

    var isInChatMode: Bool {
        windowController.isInChatMode
    }

    var isComposerInputFocused: Bool {
        windowController.isComposerInputFocused
    }

    func relayout() {
        windowController.relayout()
    }

    func update(snapshot: Snapshot) {
        self.snapshot = snapshot
        windowController.updateContext(
            screenshots: snapshot.screenshots,
            selectedTextContexts: snapshot.selectedTextContexts,
            browserPageContexts: snapshot.browserPageContexts
        )
        windowController.updateConversation(
            messages: snapshot.messages,
            isSending: snapshot.isSending,
            canCancelSend: snapshot.canCancelSend,
            conversationProvider: snapshot.conversationProvider,
            providerDisplayName: snapshot.providerDisplayName,
            hasSavedConversations: snapshot.hasSavedConversations,
            supportsWebSearch: snapshot.supportsWebSearch,
            isWebSearchEnabled: snapshot.isWebSearchEnabled
        )
    }

    func showStack(near point: NSPoint) {
        windowController.show(
            screenshots: snapshot.screenshots,
            selectedTextContexts: snapshot.selectedTextContexts,
            browserPageContexts: snapshot.browserPageContexts,
            near: point
        )
    }

    func showChat(near point: NSPoint) {
        windowController.showChat(
            screenshots: snapshot.screenshots,
            selectedTextContexts: snapshot.selectedTextContexts,
            browserPageContexts: snapshot.browserPageContexts,
            near: point
        )
    }

    func hide() {
        windowController.hide()
    }

    func handleEscapeRollback() {
        windowController.handleEscapeRollback()
    }

    func closeChat() {
        windowController.closeChat()
    }

    func updateDismissChatShortcut(_ shortcut: DismissChatShortcut) {
        windowController.updateDismissChatShortcut(shortcut)
    }

    func refreshAccessibilityDependentGlobalMonitors() {
        windowController.refreshAccessibilityDependentGlobalMonitors()
    }
}
