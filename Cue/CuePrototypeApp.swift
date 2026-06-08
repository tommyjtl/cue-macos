//
//  CuePrototypeApp.swift
//  CuePrototype
//
//  Created by Tommy Liu on 5/4/26.
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    struct DebugLogEntry: Identifiable {
        enum Source: String {
            case selectedText = "Selected Text"
            case screenshotCapture = "Screenshot Capture"
            case conversation = "Conversation"
            case persistence = "Persistence"
            case clipboard = "Clipboard"
            case obsidianNote = "Obsidian Note"
            case commandExport = "Command Export"
        }

        let id = UUID()
        let timestamp: Date
        let source: Source
        let message: String
    }

    private enum UserDefaultsKey {
        static let captureShortcut = "capture-shortcut"
        static let openChatShortcut = "open-chat-shortcut"
        static let dismissChatShortcut = "dismiss-chat-shortcut"
        static let conversationConfiguration = "conversation-configuration"
        static let obsidianExportConfiguration = "obsidian-export-configuration"
        static let saveExportConfiguration = "save-export-configuration"
        static let markExportConfiguration = "mark-export-configuration"
        static let hasCompletedOnboarding = "has-completed-onboarding"
        static let soundEffectsEnabled = AppPreferenceKeys.soundEffectsEnabledKey
        static let hideMainAppOnStart = AppPreferenceKeys.hideMainAppOnStartKey
    }

    enum SidebarSection: String, CaseIterable, Identifiable {
        case inbox
        case recents
        case debug
        case permissions
        case general
        case commands

        var id: Self { self }

        var title: String {
            switch self {
            case .inbox:
                "Sessions"
            case .recents:
                "Recents"
            case .debug:
                "Debug"
            case .permissions:
                "Permissions"
            case .general:
                "General"
            case .commands:
                "Commands"
            }
        }

        var systemImage: String {
            switch self {
            case .inbox:
                "sparkles.rectangle.stack"
            case .recents:
                "clock.arrow.circlepath"
            case .debug:
                "ladybug"
            case .permissions:
                "lock.shield"
            case .general:
                "slider.horizontal.3"
            case .commands:
                "terminal"
            }
        }
    }

    struct Milestone: Identifiable {
        let id = UUID()
        let title: String
        let summary: String
    }

    @ObservationIgnored private var hotkeyManager: HotkeyManager?
    @ObservationIgnored private var overlayCoordinator: OverlayCoordinator?
    @ObservationIgnored private var mainContentWindowController: MainContentWindowController?
    @ObservationIgnored private var contextSession: ContextSession?
    @ObservationIgnored private let conversationStore: ConversationStore?
    @ObservationIgnored private var conversationCoordinator: ConversationCoordinator?
    @ObservationIgnored private var browserWebServer: BrowserWebServer?
    @ObservationIgnored private var permissionMonitor: PermissionMonitor?
    @ObservationIgnored private var clipboardMonitor: ClipboardMonitor?
    private var hasStartedBackgroundServices = false

    // Observable permission state — updated from AppModel's stable monitoring tasks,
    // so the UI always reflects reality regardless of view rebuilds.
    var screenRecordingGranted: Bool = false
    var accessibilityGranted: Bool = false
    var needsRestartForPermissions: Bool = false

    var selectedSection: SidebarSection? = .inbox
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasCompletedOnboarding)
    var soundEffectsEnabled: Bool
    var hideMainAppOnStart: Bool
    var captureShortcut: CaptureShortcut
    var openChatShortcut: CaptureShortcut
    var dismissChatShortcut: DismissChatShortcut
    var conversationConfiguration: ConversationConfiguration
    var saveExportConfiguration: SaveExportConfiguration
    var markExportConfiguration: MarkExportConfiguration

    var obsidianExportConfiguration: SaveExportConfiguration {
        get { saveExportConfiguration }
        set { saveExportConfiguration = newValue }
    }
    let productGoal = "Capture context, ask locally, and keep the lightweight overlay workflow fast."
    var buildStatus = "Milestone 2 in progress: capture menu actions and selection overlay are wired in."
    var captureErrorMessage: String?
    var debugLogEntries: [DebugLogEntry] = []
    var capturedScreenshots: [CapturedScreenshot] = []
    var selectedTextContexts: [AttachedTextContext] = []
    var browserPageContexts: [BrowserPageContext] = []
    var conversationMessages: [ConversationMessageDTO] = []
    var savedConversations: [PersistedConversation] = []
    var selectedSavedConversationID: UUID?
    var isCaptureInProgress = false
    var isConversationInProgress = false
    var composerInFlightActivity: ComposerInFlightActivity = .none
    var isContextOverlayVisible = false
    var isContextOverlayInChatMode = false
    /// True while the user is in an overlay-driven conversation flow (started from context or resumed after collecting more context).
    private var hasActiveOverlayConversationFlow = false
    let milestones: [Milestone] = [
        .init(title: "Menu Bar Utility", summary: "Primary entry point for opening the app and the first screenshot capture path."),
        .init(title: "Main Window", summary: "Conversation-focused workspace with a stable split-view layout."),
        .init(title: "Screenshot Capture", summary: "Selection overlay and ScreenCaptureKit are now the next acceptance gate.")
    ]

    var lastCapturedScreenshot: CapturedScreenshot? {
        capturedScreenshots.first
    }

    var hasContextItems: Bool {
        !capturedScreenshots.isEmpty || !selectedTextContexts.isEmpty || !browserPageContexts.isEmpty
    }

    init() {
        let openedConversationStore: ConversationStore?
        let conversationStoreOpenError: String?
        do {
            openedConversationStore = try ConversationStore()
            conversationStoreOpenError = nil
        } catch {
            openedConversationStore = nil
            conversationStoreOpenError = error.localizedDescription
        }

        conversationStore = openedConversationStore
        soundEffectsEnabled = Self.loadSoundEffectsEnabled()
        hideMainAppOnStart = Self.loadHideMainAppOnStart()
        captureShortcut = Self.loadCaptureShortcut()
        openChatShortcut = Self.loadOpenChatShortcut()
        dismissChatShortcut = Self.loadDismissChatShortcut()
        conversationConfiguration = Self.loadConversationConfiguration()
        saveExportConfiguration = Self.loadSaveExportConfiguration()
        markExportConfiguration = Self.loadMarkExportConfiguration()
        contextSession = ContextSession { [weak self] snapshot in
            self?.applyContextSnapshot(snapshot)
        }
        conversationCoordinator = ConversationCoordinator(conversationStore: conversationStore) { [weak self] snapshot in
            self?.applyConversationSnapshot(snapshot)
        }
        let persistenceLoadError = loadPersistedConversations()
        logPersistenceHealthOnLaunch(
            storeOpenError: conversationStoreOpenError,
            loadError: persistenceLoadError
        )
    }

    func startBackgroundServicesIfNeeded() {
        guard !hasStartedBackgroundServices else {
            return
        }

        hasStartedBackgroundServices = true

        // Open main window on launch unless the user prefers menu-bar-only startup.
        Task { @MainActor in
            if shouldShowMainWindowOnLaunch {
                showMainWindow()
            }
        }

        // Start permission monitoring from AppModel (stable lifecycle).
        // This ensures permission state is never lost due to transient view rebuilds.
        startPermissionMonitoring()

        overlayCoordinator = OverlayCoordinator(
            dismissChatShortcut: dismissChatShortcut,
            onClear: { [weak self] in
                Task { @MainActor in
                    self?.clearContextStack()
                }
            },
            isCaptureInProgress: { [weak self] in
                self?.isCaptureInProgress == true
            },
            onCancelSend: { [weak self] in
                Task { @MainActor in
                    self?.cancelConversationSend()
                }
            },
            onSendDraft: { [weak self] draft in
                Task { @MainActor in
                    self?.handleConversationSend(draft)
                }
            },
            onLoadMostRecent: { [weak self] in
                Task { @MainActor in
                    self?.loadMostRecentConversationIntoOverlay()
                }
            },
            onSetWebSearchEnabled: { [weak self] isEnabled in
                Task { @MainActor in
                    self?.setOverlayWebSearchEnabled(isEnabled)
                }
            },
            onRemoveContextItem: { [weak self] item in
                Task { @MainActor in
                    self?.removeContextItemFromOverlay(item)
                }
            },
            onPresentationChange: { [weak self] in
                self?.refreshOverlayPresentationState()
            }
        )

        let browserWebServer = BrowserWebServer { [weak self] context in
            guard let self else { return .duplicate }
            return self.handleBrowserPagePush(context)
        }
        self.browserWebServer = browserWebServer
        browserWebServer.start()

        let hotkeyManager = HotkeyManager()
        self.hotkeyManager = hotkeyManager

        hotkeyManager.startMonitoring(
            captureShortcut: captureShortcut,
            openChatShortcut: openChatShortcut,
            onTrigger: { [weak self] in
                Task { @MainActor in
                    self?.handleCaptureShortcutTrigger()
                }
            },
            onConversationTrigger: { [weak self] in
                Task { @MainActor in
                    self?.beginContextConversation()
                }
            }
        )

        let clipboardMonitor = ClipboardMonitor()
        self.clipboardMonitor = clipboardMonitor
        clipboardMonitor.start(
            onAttachFromClipboard: { [weak self] text, sourceApp in
                self?.handleExternalClipboardText(text, from: sourceApp)
            },
            onDebugLog: { [weak self] message in
                self?.appendDebugLog(message, source: .clipboard)
            },
            shouldBypassAttachDetection: { [weak self] in
                if self?.overlayCoordinator?.isComposerInputFocused == true {
                    return true
                }
                return MainWindowTextInputFocus.isEditingInSettingsWindow
            }
        )
    }

    private func handleExternalClipboardText(_ text: String, from sourceApp: NSRunningApplication?) {
        guard contextSession?.attachClipboardText(text, frontmostApplication: sourceApp) == true else {
            print("[AppModel] Clipboard text already attached — \(ClipboardMonitor.preview(text))")
            return
        }

        buildStatus = "Clipboard text attached to context (double ⌘C)."
        setCaptureErrorMessage(nil, source: .selectedText)
        print("[AppModel] Attached clipboard text to context — \(ClipboardMonitor.describe(text))")
        showContextStackNearCursor()
    }

    // MARK: - Permission Monitoring

    private func startPermissionMonitoring() {
        let monitor = PermissionMonitor()
        permissionMonitor = monitor
        monitor.start { [weak self] permManager in
            self?.refreshPermissionState(from: permManager)
        }
    }

    func refreshPermissions() async {
        let permManager = PermissionManager.shared
        _ = await permManager.verifyScreenCaptureAccess(force: true)
        refreshPermissionState(from: permManager)
    }

    private func refreshPermissionState(from permManager: PermissionManager) {
        let newSR = permManager.hasScreenCapturePermission()
        let newAX = permManager.hasAccessibilityPermission()
        let newRestart = permManager.needsRestartAfterPermissionChange

        if newSR != screenRecordingGranted || newAX != accessibilityGranted || newRestart != needsRestartForPermissions {
            print("[AppModel] Permission status changed — screenRecording:\(screenRecordingGranted)→\(newSR)  accessibility:\(accessibilityGranted)→\(newAX)  needsRestart:\(needsRestartForPermissions)→\(newRestart)")
            print("[AppModel] \(permManager.permissionDiagnosticsSummary())")
        }

        screenRecordingGranted = newSR
        accessibilityGranted = newAX
        needsRestartForPermissions = newRestart

        hotkeyManager?.refreshAccessibilityDependentMonitors()
        clipboardMonitor?.refreshAccessibilityDependentMonitors()
        overlayCoordinator?.refreshAccessibilityDependentGlobalMonitors()
    }

    // MARK: - Capture

    private func handleCaptureShortcutTrigger() {
        beginScreenshotCapture()
    }

    func beginScreenshotCapture() {
        contextSession?.beginScreenshotCapture(
            setStatus: { [weak self] status in
                self?.buildStatus = status
            },
            setError: { [weak self] message in
                self?.setCaptureErrorMessage(message, source: .screenshotCapture)
            },
            onCaptureSaved: { [weak self] _ in
                self?.showContextStackNearCursor()
            }
        )
    }

    @discardableResult
    func updateCaptureShortcut(_ shortcut: CaptureShortcut) -> Bool {
        let normalizedShortcut = shortcut.normalized
        guard !normalizedShortcut.hasSameBinding(as: openChatShortcut) else {
            buildStatus = "Add-to-context shortcut conflicts with Open Chat (\(openChatShortcut.displayString)). Choose a different binding."
            return false
        }

        captureShortcut = normalizedShortcut
        hotkeyManager?.updateCaptureShortcut(normalizedShortcut)
        saveCaptureShortcut(normalizedShortcut)
        buildStatus = "Add-to-context shortcut updated to \(normalizedShortcut.displayString)."
        setCaptureErrorMessage(nil, source: .selectedText)
        return true
    }

    @discardableResult
    func updateOpenChatShortcut(_ shortcut: CaptureShortcut) -> Bool {
        let normalizedShortcut = shortcut.normalizedOpenChat()
        guard !normalizedShortcut.hasSameBinding(as: captureShortcut) else {
            buildStatus = "Open chat shortcut conflicts with Add To Context (\(captureShortcut.displayString)). Choose a different binding."
            return false
        }

        openChatShortcut = normalizedShortcut
        hotkeyManager?.updateOpenChatShortcut(normalizedShortcut)
        saveOpenChatShortcut(normalizedShortcut)
        buildStatus = "Open chat shortcut updated to \(normalizedShortcut.displayString)."
        return true
    }

    func setGlobalShortcutHandlingPaused(_ paused: Bool) {
        hotkeyManager?.setShortcutHandlingPaused(paused)
    }

    func updateDismissChatShortcut(_ shortcut: DismissChatShortcut) {
        let normalizedShortcut = shortcut.normalized
        dismissChatShortcut = normalizedShortcut
        overlayCoordinator?.updateDismissChatShortcut(normalizedShortcut)
        saveDismissChatShortcut(normalizedShortcut)
        buildStatus = "Dismiss chat shortcut updated to \(normalizedShortcut.displayString)."
    }

    func clearContextStack() {
        cancelConversationSend(resetDraftState: false)
        contextSession?.clear()
        conversationCoordinator?.clearSession()
        endOverlayConversationFlow()
        overlayCoordinator?.hide()
        refreshOverlayPresentationState()
        buildStatus = "Context stack cleared."
    }

    func removeContextItemFromOverlay(_ item: ContextPreviewItem) {
        switch item {
        case let .screenshot(screenshot):
            contextSession?.removeScreenshot(id: screenshot.id)
            buildStatus = "Removed screenshot from context."
        case let .selectedText(selectionSnapshot):
            contextSession?.removeSelectedTextContext(createdAt: selectionSnapshot.createdAt)
            buildStatus = "Removed selected text from context."
        case let .browserPage(browserPageContext):
            contextSession?.removeBrowserPage(id: browserPageContext.id)
            buildStatus = "Removed web page from context."
        }

        setCaptureErrorMessage(nil, source: .selectedText)
        syncOverlayState()
    }

    private func handleBrowserPagePush(_ context: BrowserPageContext) -> BrowserPagePushResult {
        if contextSession?.containsBrowserPage(url: context.url) ?? false {
            showContextStackNearCursor()
            buildStatus = "Web page \"\(context.pageTitle)\" is already in context."
            return .duplicate
        }

        contextSession?.addBrowserPage(context)
        showContextStackNearCursor()
        buildStatus = "Web page \"\(context.pageTitle)\" attached to context."
        return .accepted
    }

    func resumeSavedConversation(_ conversationID: UUID) {
        conversationCoordinator?.resumeConversation(conversationID)
        capturedScreenshots.removeAll()
        selectedTextContexts.removeAll()
        browserPageContexts.removeAll()
        activateOverlayConversationFlow()
        setCaptureErrorMessage(nil, source: .conversation)
        if let conversation = savedConversations.first(where: { $0.id == conversationID }) {
            buildStatus = "Loaded \(conversation.title)."
        }
        syncOverlayState()
    }

    private func loadMostRecentConversationIntoOverlay() {
        guard let mostRecent = savedConversations.first else {
            return
        }

        conversationCoordinator?.resumeConversation(mostRecent.id)
        activateOverlayConversationFlow()
        // Context (screenshots / selected text) is intentionally kept intact.
        if let conversation = savedConversations.first(where: { $0.id == mostRecent.id }) {
            buildStatus = "Loaded \(conversation.title) into the overlay."
        }
        syncOverlayState()
        overlayCoordinator?.relayout()
    }

    func dismissVisibleOverlay() {
        guard overlayCoordinator?.isVisible == true else {
            return
        }

        if overlayCoordinator?.isInChatMode == true {
            overlayCoordinator?.closeChat()
        } else {
            overlayCoordinator?.handleEscapeRollback()
        }
        refreshOverlayPresentationState()
    }

    func handleOverlayEscapeRollback() {
        dismissVisibleOverlay()
    }

    private func refreshOverlayPresentationState() {
        isContextOverlayVisible = overlayCoordinator?.isVisible ?? false
        isContextOverlayInChatMode = isContextOverlayVisible && (overlayCoordinator?.isInChatMode ?? false)

        if !isContextOverlayVisible && !hasContextItems {
            endOverlayConversationFlow()
        }
    }

    func showMainWindow() {
        if mainContentWindowController == nil {
            mainContentWindowController = MainContentWindowController(appModel: self)
        }

        mainContentWindowController?.showWindow()
    }

    func showSettingsInMainWindow() {
        selectedSection = hasRequiredPermissionsForGeneralSettings ? .general : .permissions
        showMainWindow()
    }

    var hasRequiredPermissionsForGeneralSettings: Bool {
        let permissionManager = PermissionManager.shared
        return permissionManager.hasScreenCapturePermission()
            && permissionManager.hasAccessibilityPermission()
    }

    func updateSoundEffectsEnabled(_ isEnabled: Bool) {
        soundEffectsEnabled = isEnabled
        saveSoundEffectsEnabled(isEnabled)
    }

    func updateHideMainAppOnStart(_ isEnabled: Bool) {
        hideMainAppOnStart = isEnabled
        saveHideMainAppOnStart(isEnabled)
    }

    private var shouldShowMainWindowOnLaunch: Bool {
        if !hasCompletedOnboarding {
            return true
        }

        return !hideMainAppOnStart
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
        hasCompletedOnboarding = true
    }

    func beginContextConversation() {
        if canResumeOverlayConversation {
            openContextConversationComposer()
        } else {
            openFreshContextConversationComposer()
        }
    }

    private var canResumeOverlayConversation: Bool {
        hasActiveOverlayConversationFlow && !conversationMessages.isEmpty
    }

    private func activateOverlayConversationFlow() {
        hasActiveOverlayConversationFlow = true
    }

    private func endOverlayConversationFlow() {
        hasActiveOverlayConversationFlow = false
    }

    private func openFreshContextConversationComposer() {
        endOverlayConversationFlow()
        conversationCoordinator?.clearSession()
        setCaptureErrorMessage(nil, source: .conversation)
        syncOverlayState()
        overlayCoordinator?.showChat(near: NSEvent.mouseLocation)
        refreshOverlayPresentationState()
        buildStatus = "Context composer opened."
    }

    private func openContextConversationComposer() {
        activateOverlayConversationFlow()
        setCaptureErrorMessage(nil, source: .conversation)
        syncOverlayState()
        overlayCoordinator?.showChat(near: NSEvent.mouseLocation)
        refreshOverlayPresentationState()
        buildStatus = "Context conversation resumed."
    }

    func handleConversationSend(_ draft: String) {
        activateOverlayConversationFlow()
        conversationCoordinator?.send(
            draft: draft,
            configuration: conversationConfiguration,
            saveExportConfiguration: saveExportConfiguration,
            markExportConfiguration: markExportConfiguration,
            screenshots: capturedScreenshots,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts,
            setStatus: { [weak self] status in
                self?.buildStatus = status
            },
            setError: { [weak self] message in
                self?.setCaptureErrorMessage(message, source: .conversation)
            },
            syncPanel: { [weak self] in
                self?.syncOverlayState()
            },
            onDebugLog: { [weak self] message in
                self?.appendDebugLog(message, source: .obsidianNote)
            }
        )
        contextSession?.clear()
        syncOverlayState()
    }

    func resetMarkExportSystemPrompt() {
        var configuration = markExportConfiguration
        configuration.systemPrompt = MarkExportPrompts.defaultBase
        updateMarkExportConfiguration(configuration)
    }

    func resetObsidianNoteSystemPrompt() {}

    func updateSaveExportConfiguration(_ configuration: SaveExportConfiguration) {
        saveExportConfiguration = configuration
        saveSaveExportConfiguration(configuration)
    }

    func updateMarkExportConfiguration(_ configuration: MarkExportConfiguration) {
        markExportConfiguration = configuration
        saveMarkExportConfiguration(configuration)
    }

    func updateObsidianExportConfiguration(_ configuration: SaveExportConfiguration) {
        updateSaveExportConfiguration(configuration)
    }

    func saveExportConfigurationBinding<Value>(
        for keyPath: WritableKeyPath<SaveExportConfiguration, Value>
    ) -> Binding<Value> where Value: Equatable {
        Binding(
            get: { self.saveExportConfiguration[keyPath: keyPath] },
            set: { newValue in
                var configuration = self.saveExportConfiguration
                guard configuration[keyPath: keyPath] != newValue else {
                    return
                }
                configuration[keyPath: keyPath] = newValue
                self.updateSaveExportConfiguration(configuration)
            }
        )
    }

    func markExportConfigurationBinding<Value>(
        for keyPath: WritableKeyPath<MarkExportConfiguration, Value>
    ) -> Binding<Value> where Value: Equatable {
        Binding(
            get: { self.markExportConfiguration[keyPath: keyPath] },
            set: { newValue in
                var configuration = self.markExportConfiguration
                guard configuration[keyPath: keyPath] != newValue else {
                    return
                }
                configuration[keyPath: keyPath] = newValue
                self.updateMarkExportConfiguration(configuration)
            }
        )
    }

    func obsidianExportConfigurationBinding<Value>(
        for keyPath: WritableKeyPath<SaveExportConfiguration, Value>
    ) -> Binding<Value> where Value: Equatable {
        saveExportConfigurationBinding(for: keyPath)
    }

    func updateConversationConfiguration(_ configuration: ConversationConfiguration) {
        conversationConfiguration = configuration
        saveConversationConfiguration(configuration)
        syncOverlayState()
    }

    func conversationConfigurationBinding<Value>(
        for keyPath: WritableKeyPath<ConversationConfiguration, Value>
    ) -> Binding<Value> where Value: Equatable {
        Binding(
            get: { self.conversationConfiguration[keyPath: keyPath] },
            set: { newValue in
                var configuration = self.conversationConfiguration
                guard configuration[keyPath: keyPath] != newValue else {
                    return
                }
                configuration[keyPath: keyPath] = newValue
                self.updateConversationConfiguration(configuration)
            }
        )
    }

    func setOverlayWebSearchEnabled(_ isEnabled: Bool) {
        var updatedConfiguration = conversationConfiguration
        updatedConfiguration.setWebSearchEnabled(isEnabled)
        updateConversationConfiguration(updatedConfiguration)
    }

    func cancelConversationSend(resetDraftState: Bool = true) {
        conversationCoordinator?.cancelSend(
            setError: { [weak self] message in
                self?.setCaptureErrorMessage(message, source: .conversation)
            },
            syncPanel: { [weak self] in
                self?.syncOverlayState()
            }
        )
    }

    /// Presents newly collected context in the overlay. Keeps chat mode when the composer is already open.
    private func showContextStackNearCursor() {
        syncOverlayState()

        if overlayCoordinator?.isInChatMode == true {
            overlayCoordinator?.relayout()
            overlayCoordinator?.focusChatComposer()
            refreshOverlayPresentationState()
            return
        }

        overlayCoordinator?.showStack(near: NSEvent.mouseLocation)
        refreshOverlayPresentationState()
    }

    func resetCaptureShortcutToDefault() {
        updateCaptureShortcut(.defaultValue)
    }

    func resetOpenChatShortcutToDefault() {
        updateOpenChatShortcut(.defaultOpenChatValue)
    }

    func resetDismissChatShortcutToDefault() {
        updateDismissChatShortcut(.defaultValue)
    }

    private static func loadCaptureShortcut() -> CaptureShortcut {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.captureShortcut) else {
            return .defaultValue
        }

        do {
            return try JSONDecoder().decode(CaptureShortcut.self, from: data).normalized
        } catch {
            return .defaultValue
        }
    }

    private func saveCaptureShortcut(_ shortcut: CaptureShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.captureShortcut)
    }

    private static func loadOpenChatShortcut() -> CaptureShortcut {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.openChatShortcut) else {
            return .defaultOpenChatValue
        }

        do {
            return try JSONDecoder().decode(CaptureShortcut.self, from: data).normalizedOpenChat()
        } catch {
            return .defaultOpenChatValue
        }
    }

    private func saveOpenChatShortcut(_ shortcut: CaptureShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.openChatShortcut)
    }

    private static func loadDismissChatShortcut() -> DismissChatShortcut {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.dismissChatShortcut) else {
            return .defaultValue
        }

        do {
            return try JSONDecoder().decode(DismissChatShortcut.self, from: data).normalized
        } catch {
            return .defaultValue
        }
    }

    private func saveDismissChatShortcut(_ shortcut: DismissChatShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.dismissChatShortcut)
    }

    private static func loadConversationConfiguration() -> ConversationConfiguration {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.conversationConfiguration) else {
            return .defaultValue
        }

        do {
            return try JSONDecoder().decode(ConversationConfiguration.self, from: data)
        } catch {
            return .defaultValue
        }
    }

    private func saveConversationConfiguration(_ configuration: ConversationConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.conversationConfiguration)
    }

    private static func loadSaveExportConfiguration() -> SaveExportConfiguration {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKey.saveExportConfiguration),
           let configuration = try? JSONDecoder().decode(SaveExportConfiguration.self, from: data) {
            return configuration
        }

        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.obsidianExportConfiguration) else {
            return .defaultValue
        }

        do {
            return try JSONDecoder().decode(SaveExportConfiguration.self, from: data)
        } catch {
            return .defaultValue
        }
    }

    private static func loadMarkExportConfiguration() -> MarkExportConfiguration {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.markExportConfiguration) else {
            return .defaultValue
        }

        do {
            return try JSONDecoder().decode(MarkExportConfiguration.self, from: data)
        } catch {
            return .defaultValue
        }
    }

    private func saveSaveExportConfiguration(_ configuration: SaveExportConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.saveExportConfiguration)
    }

    private func saveMarkExportConfiguration(_ configuration: MarkExportConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }

        UserDefaults.standard.set(data, forKey: UserDefaultsKey.markExportConfiguration)
    }

    func resetConversationConfiguration() {
        saveConversationConfiguration(.defaultValue)
        conversationConfiguration = .defaultValue
    }

    private static func loadSoundEffectsEnabled() -> Bool {
        AppPreferenceKeys.soundEffectsEnabled
    }

    private func saveSoundEffectsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKey.soundEffectsEnabled)
    }

    private static func loadHideMainAppOnStart() -> Bool {
        AppPreferenceKeys.hideMainAppOnStart
    }

    private func saveHideMainAppOnStart(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKey.hideMainAppOnStart)
    }

    private func syncOverlayState() {
        overlayCoordinator?.update(
            snapshot: OverlayCoordinator.Snapshot(
                screenshots: capturedScreenshots,
                selectedTextContexts: selectedTextContexts,
                browserPageContexts: browserPageContexts,
                messages: conversationMessages,
                isSending: isConversationInProgress,
                canCancelSend: isConversationInProgress,
                inFlightActivity: composerInFlightActivity,
                conversationProvider: conversationConfiguration.provider,
                providerDisplayName: conversationConfiguration.providerDisplayName,
                hasSavedConversations: !savedConversations.isEmpty,
                supportsWebSearch: conversationConfiguration.provider.supportsWebSearch,
                isWebSearchEnabled: conversationConfiguration.usesWebSearch
            )
        )
    }

    @discardableResult
    private func loadPersistedConversations() -> String? {
        var loadError: String?
        conversationCoordinator?.loadPersistedConversations(onError: { [weak self] message in
            loadError = message
            self?.setCaptureErrorMessage(message, source: .persistence)
        })
        return loadError
    }

    private func logPersistenceHealthOnLaunch(storeOpenError: String?, loadError: String?) {
        let loadedMessageCount = savedConversations.reduce(0) { partial, conversation in
            partial + conversation.messages.count
        }
        let lines = PersistenceHealthDiagnostics.launchReportLines(
            context: PersistenceHealthDiagnostics.LaunchContext(
                storeOpenError: storeOpenError,
                loadedConversationCount: savedConversations.count,
                loadedMessageCount: loadedMessageCount,
                loadError: loadError
            )
        )
        appendDebugLog(lines.joined(separator: "\n"), source: .persistence)
    }

    func clearDebugLog() {
        debugLogEntries.removeAll()
    }

    func appendDebugLog(_ message: String, source: DebugLogEntry.Source) {
        debugLogEntries.insert(
            DebugLogEntry(timestamp: Date(), source: source, message: message),
            at: 0
        )

        if debugLogEntries.count > 100 {
            debugLogEntries.removeLast(debugLogEntries.count - 100)
        }

        print("[DebugLog][\(source.rawValue)] \(message)")
    }

    private func setCaptureErrorMessage(_ message: String?, source: DebugLogEntry.Source) {
        captureErrorMessage = message

        guard let message, !message.isEmpty else {
            return
        }

        if let latestEntry = debugLogEntries.first,
           latestEntry.source == source,
           latestEntry.message == message {
            return
        }

        debugLogEntries.insert(
            DebugLogEntry(timestamp: Date(), source: source, message: message),
            at: 0
        )

        if debugLogEntries.count > 100 {
            debugLogEntries.removeLast(debugLogEntries.count - 100)
        }
    }

    private func applyConversationSnapshot(_ snapshot: ConversationCoordinator.SessionSnapshot) {
        conversationMessages = snapshot.messages
        savedConversations = snapshot.savedConversations
        selectedSavedConversationID = snapshot.selectedSavedConversationID
        isConversationInProgress = snapshot.isConversationInProgress
        composerInFlightActivity = snapshot.inFlightActivity
        syncOverlayState()
    }

    private func applyContextSnapshot(_ snapshot: ContextSession.Snapshot) {
        let previousContextItemCount = contextItemCount

        capturedScreenshots = snapshot.capturedScreenshots
        selectedTextContexts = snapshot.selectedTextContexts
        browserPageContexts = snapshot.browserPageContexts
        isCaptureInProgress = snapshot.isCaptureInProgress

        if contextItemCount > previousContextItemCount {
            SoundEffectPlayer.play(.contextAttached)
        }

        syncOverlayState()
    }

    private var contextItemCount: Int {
        capturedScreenshots.count + selectedTextContexts.count + browserPageContexts.count
    }
}

/// Menu-bar apps use `.accessory` by default; the settings window needs `.regular` for text fields and copy/paste.
enum MainWindowActivationPolicy {
    static func applyForMainSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func restoreMenuBarAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var commandQMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        installCommandQMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let commandQMonitor {
            NSEvent.removeMonitor(commandQMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installCommandQMonitor() {
        commandQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command),
                  !flags.contains(.shift),
                  !flags.contains(.option),
                  !flags.contains(.control),
                  event.charactersIgnoringModifiers?.lowercased() == "q" else {
                return event
            }

            NSApp.terminate(nil)
            return nil
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = NSMenuItem(
            title: "Quit Cue",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

enum MainWindowTextInputFocus {
    static var isEditingInSettingsWindow: Bool {
        guard let window = NSApp.keyWindow,
              window.title == "Cue",
              NSApp.isActive else {
            return false
        }

        guard let responder = window.firstResponder else {
            return false
        }

        return responder is NSTextView || responder is NSTextField
    }
}

/// Routes standard edit shortcuts to SwiftUI text fields hosted in the settings window.
private final class MainSettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }

        guard let firstResponder else {
            return false
        }

        return ComposerEditShortcut.perform(with: event, sender: firstResponder)
    }
}

@MainActor
final class MainContentWindowController: NSWindowController, NSWindowDelegate {
    private var editShortcutMonitor: Any?

    init(appModel: AppModel) {
        let hostingController = NSHostingController(
            rootView: ContentView()
                .environment(appModel)
                .frame(
                    minWidth: SettingsLayout.MainWindow.minWidth,
                    minHeight: SettingsLayout.MainWindow.minHeight
                )
        )
        let window = MainSettingsWindow(contentViewController: hostingController)

        window.title = "Cue"
        window.setContentSize(
            NSSize(
                width: SettingsLayout.MainWindow.defaultWidth,
                height: SettingsLayout.MainWindow.defaultHeight
            )
        )
        window.minSize = NSSize(
            width: SettingsLayout.MainWindow.minWidth,
            height: SettingsLayout.MainWindow.minHeight
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)
        window.delegate = self
        clampWindowFrameIfNeeded()
        installEditShortcutMonitor()
    }

    deinit {
        if let editShortcutMonitor {
            NSEvent.removeMonitor(editShortcutMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        guard let window else {
            return
        }

        clampWindowFrameIfNeeded()
        MainWindowActivationPolicy.applyForMainSettingsWindow()
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        MainWindowActivationPolicy.applyForMainSettingsWindow()
    }

    func windowWillClose(_ notification: Notification) {
        MainWindowActivationPolicy.restoreMenuBarAccessoryPolicy()
    }

    private func installEditShortcutMonitor() {
        editShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window === NSApp.keyWindow,
                  ComposerEditShortcut.selector(for: event) != nil else {
                return event
            }

            let sender = window.firstResponder ?? window
            if ComposerEditShortcut.perform(with: event, sender: sender) {
                return nil
            }

            return event
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, SettingsLayout.MainWindow.minWidth),
            height: max(frameSize.height, SettingsLayout.MainWindow.minHeight)
        )
    }

    private func clampWindowFrameIfNeeded() {
        guard let window else {
            return
        }

        var frame = window.frame
        let minWidth = SettingsLayout.MainWindow.minWidth
        let minHeight = SettingsLayout.MainWindow.minHeight
        guard frame.width < minWidth || frame.height < minHeight else {
            return
        }

        frame.size = NSSize(
            width: max(frame.width, minWidth),
            height: max(frame.height, minHeight)
        )
        window.setFrame(frame, display: true)
    }
}

@main
@MainActor
struct CuePrototypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppModel

    init() {
        let appState = AppModel()
        appState.startBackgroundServicesIfNeeded()
        _appState = State(initialValue: appState)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(appState)
        } label: {
            MenuBarIconLabel()
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandMenu("Capture") {
                Button("Capture Screenshot") {
                    appState.beginScreenshotCapture()
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(appState.isCaptureInProgress)

                Button("Clear Context Stack") {
                    appState.clearContextStack()
                }
                .disabled(!appState.hasContextItems)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettingsInMainWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .appTermination) {
                Button("Quit Cue") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }
}

private struct MenuBarIconLabel: View {
    var body: some View {
        Image(nsImage: MenuBarIcon.templateImage)
            .accessibilityLabel("Cue")
    }
}

private struct MenuBarContentView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        Button("Open App") {
            appState.showMainWindow()
        }

        if appState.isContextOverlayInChatMode {
            Button("Dismiss Chat UI") {
                appState.dismissVisibleOverlay()
            }
        } else if appState.isContextOverlayVisible && appState.hasContextItems {
            Button("Dismiss Context") {
                appState.dismissVisibleOverlay()
            }
        }

        Divider()

        Picker("Provider", selection: appState.conversationConfigurationBinding(for: \.provider)) {
            ForEach(ConversationProvider.allCases) { provider in
                Text(provider.title).tag(provider)
            }
        }

        Button("Settings") {
            appState.showSettingsInMainWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Cue") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

struct StartupSettingsSection: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(
                    title: "Hide main app on start",
                    subtitle: appState.hideMainAppOnStart ? "On" : "Off"
                ) {
                    Toggle("Hide main app on start", isOn: hideMainAppOnStartBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsFootnote("When on, Cue stays in the menu bar at launch. Open the main window from the menu bar or Settings… (⌘,). Onboarding still opens the window the first time.")
        }
    }

    private var hideMainAppOnStartBinding: Binding<Bool> {
        Binding(
            get: { appState.hideMainAppOnStart },
            set: { appState.updateHideMainAppOnStart($0) }
        )
    }
}

struct SoundEffectsSettingsSection: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                SettingsRow(
                    title: "Sound effects",
                    subtitle: appState.soundEffectsEnabled ? "On" : "Off"
                ) {
                    Toggle("Play sound effects", isOn: soundEffectsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsFootnote("Plays when context is attached or chat opens. Requires macOS \"Play user interface sound effects\" in System Settings → Sound.")
        }
    }

    private var soundEffectsBinding: Binding<Bool> {
        Binding(
            get: { appState.soundEffectsEnabled },
            set: { appState.updateSoundEffectsEnabled($0) }
        )
    }
}

struct ConversationSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var availableOllamaModels = OllamaModelCatalog.fallbackOptions
    @State private var isRefreshingOllamaModels = false
    @State private var ollamaModelsStatus: String?

    private let ollamaModelDiscoveryService = OllamaModelDiscoveryService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Provider")

            SettingsCard {
                SettingsCardBody {
                    SettingsFieldGroup(label: "Provider") {
                        Picker("Provider", selection: appState.conversationConfigurationBinding(for: \.provider)) {
                            ForEach(ConversationProvider.allCases) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }

                SettingsRowDivider()

                switch appState.conversationConfiguration.provider {
                case .ollama:
                    ollamaProviderCardContent
                case .openAI:
                    openAIProviderCardContent
                }
            }

            providerFootnotes(outsideCardNotes)
        }
        .onAppear {
            availableOllamaModels = OllamaModelCatalog.mergedOptions(
                OllamaModelCatalog.fallbackOptions,
                currentModelName: appState.conversationConfiguration.ollamaModel
            )
            normalizeOllamaThinkingMode()

            Task {
                await refreshOllamaModels()
            }
        }
        .onChange(of: appState.conversationConfiguration.ollamaModel, initial: false) { _, _ in
            normalizeOllamaThinkingMode()
        }
    }

    @ViewBuilder
    private var ollamaProviderCardContent: some View {
        SettingsCardBody {
            SettingsFieldGroup(label: "Base URL") {
                TextField("http://localhost:11434", text: appState.conversationConfigurationBinding(for: \.ollamaBaseURL))
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFieldGroup(label: "Model") {
                Picker("Model", selection: appState.conversationConfigurationBinding(for: \.ollamaModel)) {
                    ForEach(availableOllamaModels) { option in
                        Text(option.pickerTitle).tag(option.modelName)
                    }
                }
                .labelsHidden()

                HStack {
                    Button(isRefreshingOllamaModels ? "Refreshing..." : "Refresh Models") {
                        Task {
                            await refreshOllamaModels()
                        }
                    }
                    .disabled(isRefreshingOllamaModels)

                    Spacer()

                    Text(selectedOllamaModelOption.source == .installed ? "Installed via /api/tags" : "Curated fallback")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            ollamaThinkingControl

            SettingsFieldGroup(label: "API Key") {
                SecureField("Ollama API Key", text: appState.conversationConfigurationBinding(for: \.ollamaAPIKey))
                    .textFieldStyle(.roundedBorder)
            }
        }

        SettingsRowDivider()

        SettingsToggleRow(
            title: "Web Search",
            subtitle: webSearchSubtitle,
            isOn: appState.conversationConfigurationBinding(for: \.ollamaUseWebSearch)
        )
    }

    @ViewBuilder
    private var openAIProviderCardContent: some View {
        SettingsCardBody {
            SettingsFieldGroup(label: "Model") {
                HStack {
                    TextField("gpt-5.4", text: appState.conversationConfigurationBinding(for: \.openAIModel))
                        .textFieldStyle(.roundedBorder)

                    SettingsChangeButton("Reset") {
                        appState.resetConversationConfiguration()
                    }
                }
            }

            SettingsFieldGroup(label: "API Key") {
                SecureField("OpenAI API Key", text: appState.conversationConfigurationBinding(for: \.openAIAPIKey))
                    .textFieldStyle(.roundedBorder)
            }
        }

        SettingsRowDivider()

        SettingsToggleRow(
            title: "Web Search",
            subtitle: webSearchSubtitle,
            isOn: appState.conversationConfigurationBinding(for: \.openAIUseWebSearch)
        )
    }

    private var webSearchSubtitle: String {
        switch appState.conversationConfiguration.provider {
        case .ollama:
            "Use Ollama hosted web search and fetch tools for current information."
        case .openAI:
            "Use the OpenAI Responses API web search tool for current information."
        }
    }

    @ViewBuilder
    private var ollamaThinkingControl: some View {
        switch selectedOllamaModelOption.thinkingSupport {
        case .unsupported:
            SettingsFieldGroup(label: "Thinking") {
                Text("Unavailable for this model")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .toggle:
            SettingsFieldGroup(label: "Thinking") {
                Toggle("Enable extended reasoning for supported Ollama models.", isOn: ollamaThinkingToggleBinding)
            }
        case let .levels(modes):
            SettingsFieldGroup(label: "Thinking") {
                Picker("Thinking", selection: appState.conversationConfigurationBinding(for: \.ollamaThinkingMode)) {
                    ForEach(modes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var outsideCardNotes: [String?] {
        switch appState.conversationConfiguration.provider {
        case .ollama:
            return [
                "API keys are stored in UserDefaults for the prototype. Move this to Keychain before shipping.",
                selectedOllamaModelOption.summary,
                selectedOllamaModelOption.thinkingSupport.statusDescription,
                ollamaModelsStatus
            ]
        case .openAI:
            return [
                "API keys are stored in UserDefaults for the prototype. Move this to Keychain before shipping."
            ]
        }
    }

    @ViewBuilder
    private func providerFootnotes(_ notes: [String?]) -> some View {
        ForEach(notes.compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { note in
            SettingsFootnote(note)
        }
    }

    private var selectedOllamaModelOption: OllamaModelOption {
        availableOllamaModels.first(where: { $0.modelName == appState.conversationConfiguration.ollamaModel })
            ?? OllamaModelCatalog.option(for: appState.conversationConfiguration.ollamaModel, source: .current)
    }

    private var ollamaThinkingToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.conversationConfiguration.ollamaThinkingMode == .on },
            set: { isEnabled in
                var configuration = appState.conversationConfiguration
                configuration.ollamaThinkingMode = isEnabled ? .on : .off
                appState.updateConversationConfiguration(configuration)
            }
        )
    }

    @MainActor
    private func refreshOllamaModels() async {
        isRefreshingOllamaModels = true
        defer { isRefreshingOllamaModels = false }

        do {
            let discoveredModels = try await ollamaModelDiscoveryService.fetchAvailableModels(baseURL: appState.conversationConfiguration.ollamaBaseURL)
            availableOllamaModels = OllamaModelCatalog.mergedOptions(discoveredModels, currentModelName: appState.conversationConfiguration.ollamaModel)
            ollamaModelsStatus = discoveredModels.isEmpty
                ? "No installed Ollama models were returned. Showing the current configuration only."
                : "Loaded \(discoveredModels.count) installed model(s) from Ollama."
        } catch {
            availableOllamaModels = OllamaModelCatalog.mergedOptions(OllamaModelCatalog.fallbackOptions, currentModelName: appState.conversationConfiguration.ollamaModel)
            ollamaModelsStatus = "Could not load installed Ollama models. Showing curated model options instead."
        }

        normalizeOllamaThinkingMode()
    }

    private func normalizeOllamaThinkingMode() {
        var configuration = appState.conversationConfiguration
        let normalizedMode = selectedOllamaModelOption.thinkingSupport.normalized(configuration.ollamaThinkingMode)
        guard configuration.ollamaThinkingMode != normalizedMode else {
            return
        }
        configuration.ollamaThinkingMode = normalizedMode
        appState.updateConversationConfiguration(configuration)
    }
}


