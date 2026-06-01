import SwiftUI

struct ShortcutSettingsSection: View {
    @Environment(AppModel.self) private var appState

    private enum ActiveShortcutRecording {
        case openChat
        case addToContext
    }

    @State private var activeRecording: ActiveShortcutRecording?
    @State private var openChatPreviewTokens: [String] = []
    @State private var capturePreviewTokens: [String] = []
    @State private var openChatRecordingSession = CaptureShortcutRecordingSession(
        doubleModifierOptions: CaptureShortcut.doubleModifierOptionsWithShift,
        normalize: { $0.normalizedOpenChat() }
    )
    @State private var captureRecordingSession = CaptureShortcutRecordingSession()

    var body: some View {
        SettingsCard {
            ShortcutSettingInlineRow(
                title: ShortcutFeatureCopy.openChatName,
                tokens: openChatPreviewTokens,
                isRecording: activeRecording == .openChat,
                isChangeDisabled: activeRecording != nil,
                onChange: { beginRecording(.openChat) },
                onEvent: handleOpenChatRecordingEvent,
                onCancelRecording: { cancelRecording(.openChat) }
            )

            SettingsRowDivider()

            ShortcutSettingReadOnlyRow(
                title: ShortcutFeatureCopy.dismissChatName,
                tokens: DismissChatShortcut.defaultValue.displayTokens
            )

            SettingsRowDivider()

            ShortcutSettingInlineRow(
                title: ShortcutFeatureCopy.addToContextName,
                tokens: capturePreviewTokens,
                isRecording: activeRecording == .addToContext,
                isChangeDisabled: activeRecording != nil,
                onChange: { beginRecording(.addToContext) },
                onEvent: handleCaptureRecordingEvent,
                onCancelRecording: { cancelRecording(.addToContext) }
            )
        }
        .onAppear {
            refreshPreviewTokensFromAppState()
        }
        .onChange(of: appState.openChatShortcut) { _, _ in
            guard activeRecording != .openChat else { return }
            openChatPreviewTokens = appState.openChatShortcut.displayTokens
        }
        .onChange(of: appState.captureShortcut) { _, _ in
            guard activeRecording != .addToContext else { return }
            capturePreviewTokens = appState.captureShortcut.displayTokens
        }
    }

    private func refreshPreviewTokensFromAppState() {
        openChatPreviewTokens = appState.openChatShortcut.displayTokens
        capturePreviewTokens = appState.captureShortcut.displayTokens
    }

    private func beginRecording(_ role: ActiveShortcutRecording) {
        activeRecording = role

        switch role {
        case .openChat:
            openChatRecordingSession.reset()
            openChatPreviewTokens = []
        case .addToContext:
            captureRecordingSession.reset()
            capturePreviewTokens = []
        }
    }

    private func cancelRecording(_ role: ActiveShortcutRecording) {
        guard activeRecording == role else { return }
        activeRecording = nil
        refreshPreviewTokensFromAppState()
    }

    private func finishRecording(_ role: ActiveShortcutRecording) {
        guard activeRecording == role else { return }
        activeRecording = nil
    }

    private func handleOpenChatRecordingEvent(_ event: NSEvent) -> Bool {
        if let shortcut = openChatRecordingSession.handle(event) {
            let normalized = shortcut.normalizedOpenChat()
            openChatPreviewTokens = normalized.displayTokens
            appState.updateOpenChatShortcut(normalized)
            finishRecording(.openChat)
            return true
        }

        openChatPreviewTokens = openChatRecordingSession.previewTokens
        return false
    }

    private func handleCaptureRecordingEvent(_ event: NSEvent) -> Bool {
        if let shortcut = captureRecordingSession.handle(event) {
            let normalized = shortcut.normalized
            capturePreviewTokens = normalized.displayTokens
            appState.updateCaptureShortcut(normalized)
            finishRecording(.addToContext)
            return true
        }

        capturePreviewTokens = captureRecordingSession.previewTokens
        return false
    }
}
