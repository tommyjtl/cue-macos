import AppKit
import Foundation

@MainActor
final class OverlayCoordinator {
    struct Snapshot {
        var screenshots: [CapturedScreenshot] = []
        var selectedTextContexts: [SelectedTextManager.SelectionSnapshot] = []
        var browserPageContexts: [BrowserPageContext] = []
        var messages: [ConversationMessageDTO] = []
        var isSending = false
        var canCancelSend = false
        var providerDisplayName = ""
        var hasSavedConversations = false
        var supportsWebSearch = false
        var isWebSearchEnabled = false
    }

    private let windowController: ContextStackWindowController
    private var snapshot = Snapshot()

    init(
        onClear: @escaping () -> Void,
        onAppDeactivate: @escaping () -> Void,
        isCaptureInProgress: @escaping () -> Bool,
        onCancelSend: @escaping () -> Void,
        onSendDraft: @escaping (String) -> Void,
        onLoadMostRecent: @escaping () -> Void,
        onSetWebSearchEnabled: @escaping (Bool) -> Void,
        onRemoveContextItem: @escaping (ContextPreviewItem) -> Void
    ) {
        windowController = ContextStackWindowController(
            onClear: onClear,
            onAppDeactivate: onAppDeactivate,
            isCaptureInProgress: isCaptureInProgress,
            onCancelSend: onCancelSend,
            onSendDraft: onSendDraft,
            onLoadMostRecent: onLoadMostRecent,
            onSetWebSearchEnabled: onSetWebSearchEnabled,
            onRemoveContextItem: onRemoveContextItem
        )
    }

    var isVisible: Bool {
        windowController.isVisible
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
}