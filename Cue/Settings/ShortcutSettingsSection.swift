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
    @State private var pendingOpenChatShortcut: CaptureShortcut?
    @State private var pendingCaptureShortcut: CaptureShortcut?
    @State private var isOpenChatRecorderFocused = false
    @State private var isCaptureRecorderFocused = false
    @State private var recordingEventTap = ShortcutRecordingEventTap()
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
                isFocused: isOpenChatRecorderFocused,
                canCommit: canCommitOpenChat,
                isChangeDisabled: activeRecording != nil,
                onChange: { beginRecording(.openChat) },
                onDone: { commitRecording(.openChat) },
                onEvent: handleOpenChatRecordingEvent,
                onCancelRecording: { cancelRecording(.openChat) },
                onFocusChange: { isOpenChatRecorderFocused = $0 }
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
                isFocused: isCaptureRecorderFocused,
                canCommit: canCommitCapture,
                isChangeDisabled: activeRecording != nil,
                onChange: { beginRecording(.addToContext) },
                onDone: { commitRecording(.addToContext) },
                onEvent: handleCaptureRecordingEvent,
                onCancelRecording: { cancelRecording(.addToContext) },
                onFocusChange: { isCaptureRecorderFocused = $0 }
            )
        }
        .onAppear {
            refreshPreviewTokensFromAppState()
        }
        .onDisappear {
            stopRecordingSession()
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

    private var canCommitOpenChat: Bool {
        pendingOpenChatShortcut != nil || openChatRecordingSession.hasPendingModifierOnly
    }

    private var canCommitCapture: Bool {
        pendingCaptureShortcut != nil || captureRecordingSession.hasPendingModifierOnly
    }

    private func refreshPreviewTokensFromAppState() {
        openChatPreviewTokens = appState.openChatShortcut.displayTokens
        capturePreviewTokens = appState.captureShortcut.displayTokens
    }

    private func beginRecording(_ role: ActiveShortcutRecording) {
        stopRecordingSession()

        activeRecording = role
        isOpenChatRecorderFocused = false
        isCaptureRecorderFocused = false

        switch role {
        case .openChat:
            openChatRecordingSession.reset()
            pendingOpenChatShortcut = nil
            openChatPreviewTokens = []
        case .addToContext:
            captureRecordingSession.reset()
            pendingCaptureShortcut = nil
            capturePreviewTokens = []
        }

        appState.setGlobalShortcutHandlingPaused(true)
        recordingEventTap.start { event in
            if event.type == .keyDown, event.keyCode == 53 {
                cancelRecording(role)
                return
            }

            switch role {
            case .openChat:
                _ = handleOpenChatRecordingEvent(event)
            case .addToContext:
                _ = handleCaptureRecordingEvent(event)
            }
        }
    }

    private func cancelRecording(_ role: ActiveShortcutRecording) {
        guard activeRecording == role else { return }
        pendingOpenChatShortcut = nil
        pendingCaptureShortcut = nil
        stopRecordingSession()
        refreshPreviewTokensFromAppState()
    }

    private func finishRecording(_ role: ActiveShortcutRecording) {
        guard activeRecording == role else { return }
        stopRecordingSession()
    }

    private func stopRecordingSession() {
        recordingEventTap.stop()
        appState.setGlobalShortcutHandlingPaused(false)
        isOpenChatRecorderFocused = false
        isCaptureRecorderFocused = false
        activeRecording = nil
        openChatRecordingSession.reset()
        captureRecordingSession.reset()
        pendingOpenChatShortcut = nil
        pendingCaptureShortcut = nil
    }

    private func commitRecording(_ role: ActiveShortcutRecording) {
        guard activeRecording == role else { return }

        switch role {
        case .openChat:
            if let pendingOpenChatShortcut {
                appState.updateOpenChatShortcut(pendingOpenChatShortcut)
            } else if let modifierOnly = openChatRecordingSession.consumePendingModifierOnlyIfReady()?.normalizedOpenChat() {
                appState.updateOpenChatShortcut(modifierOnly)
            } else {
                return
            }
        case .addToContext:
            if let pendingCaptureShortcut {
                appState.updateCaptureShortcut(pendingCaptureShortcut)
            } else if let modifierOnly = captureRecordingSession.consumePendingModifierOnlyIfReady()?.normalized {
                appState.updateCaptureShortcut(modifierOnly)
            } else {
                return
            }
        }

        refreshPreviewTokensFromAppState()
        finishRecording(role)
    }

    private func handleOpenChatRecordingEvent(_ event: NSEvent) -> Bool {
        guard activeRecording == .openChat else { return false }

        if let shortcut = openChatRecordingSession.handle(event) {
            pendingOpenChatShortcut = shortcut.normalizedOpenChat()
            openChatPreviewTokens = pendingOpenChatShortcut?.displayTokens ?? []
            return true
        }

        openChatPreviewTokens = openChatRecordingSession.previewTokens
        return true
    }

    private func handleCaptureRecordingEvent(_ event: NSEvent) -> Bool {
        guard activeRecording == .addToContext else { return false }

        if let shortcut = captureRecordingSession.handle(event) {
            pendingCaptureShortcut = shortcut.normalized
            capturePreviewTokens = pendingCaptureShortcut?.displayTokens ?? []
            return true
        }

        capturePreviewTokens = captureRecordingSession.previewTokens
        return true
    }
}
