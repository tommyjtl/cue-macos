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
        }

        let id = UUID()
        let timestamp: Date
        let source: Source
        let message: String
    }

    private enum UserDefaultsKey {
        static let captureShortcut = "capture-shortcut"
        static let conversationConfiguration = "conversation-configuration"
        static let hasCompletedOnboarding = "has-completed-onboarding"
    }

    enum SidebarSection: String, CaseIterable, Identifiable {
        case inbox
        case recents
        case debug
        case permissions
        case shortcuts
        case providers

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
            case .shortcuts:
                "Shortcuts"
            case .providers:
                "Providers"
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
            case .shortcuts:
                "keyboard"
            case .providers:
                "server.rack"
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
    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var permissionPollTask: Task<Void, Never>?
    private var hasStartedBackgroundServices = false

    // Observable permission state — updated from AppModel's stable monitoring tasks,
    // so the UI always reflects reality regardless of view rebuilds.
    var screenRecordingGranted: Bool = false
    var accessibilityGranted: Bool = false
    var needsRestartForPermissions: Bool = false

    var selectedSection: SidebarSection? = .inbox
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasCompletedOnboarding)
    var captureShortcut: CaptureShortcut
    var conversationConfiguration: ConversationConfiguration
    let productGoal = "Capture context, ask locally, and keep the lightweight overlay workflow fast."
    var buildStatus = "Milestone 2 in progress: capture menu actions and selection overlay are wired in."
    var captureErrorMessage: String?
    var debugLogEntries: [DebugLogEntry] = []
    var capturedScreenshots: [CapturedScreenshot] = []
    var selectedTextContexts: [SelectedTextManager.SelectionSnapshot] = []
    var browserPageContexts: [BrowserPageContext] = []
    var conversationMessages: [ConversationMessageDTO] = []
    var savedConversations: [PersistedConversation] = []
    var selectedSavedConversationID: UUID?
    var isCaptureInProgress = false
    var isConversationInProgress = false
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
        conversationStore = try? ConversationStore()
        captureShortcut = Self.loadCaptureShortcut()
        conversationConfiguration = Self.loadConversationConfiguration()
        contextSession = ContextSession { [weak self] snapshot in
            self?.applyContextSnapshot(snapshot)
        }
        conversationCoordinator = ConversationCoordinator(conversationStore: conversationStore) { [weak self] snapshot in
            self?.applyConversationSnapshot(snapshot)
        }
        loadPersistedConversations()
    }

    func startBackgroundServicesIfNeeded() {
        guard !hasStartedBackgroundServices else {
            return
        }

        hasStartedBackgroundServices = true

        // Open main window on every app launch.
        Task { @MainActor in
            showMainWindow()
        }

        // Start permission monitoring from AppModel (stable lifecycle).
        // This ensures permission state is never lost due to transient view rebuilds.
        startPermissionMonitoring()

        overlayCoordinator = OverlayCoordinator(
            onClear: { [weak self] in
                Task { @MainActor in
                    self?.clearContextStack()
                }
            },
            onAppDeactivate: { [weak self] in
                Task { @MainActor in
                    self?.handleAppDeactivationWhileContextVisible()
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
            shortcut: captureShortcut,
            onTrigger: { [weak self] in
                Task { @MainActor in
                    self?.handleCaptureShortcutTrigger()
                }
            },
            onConversationTrigger: { [weak self] in
                Task { @MainActor in
                    self?.beginContextConversation()
                }
            },
            onDismissOverlayTrigger: { [weak self] in
                Task { @MainActor in
                    self?.dismissVisibleContextOverlayIfNeeded()
                }
            },
            onPrefetchSelectedText: { [weak self] in
                Task { @MainActor in
                    self?.contextSession?.prefetchSelectedTextCapture()
                }
            }
        )
    }

    // MARK: - Permission Monitoring

    private func startPermissionMonitoring() {
        let permManager = PermissionManager.shared

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await permManager.registerScreenCaptureIfNeeded()
            refreshPermissionState(from: permManager)
        }

        permissionMonitorTask = Task { [weak self] in
            let stream = Self.axPermissionNotificationStream()
            for await _ in stream {
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshPermissionState(from: permManager)
            }
        }

        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissionState(from: permManager)
                let delay: Duration = (self?.hasAllPermissionsGranted == true) ? .seconds(2) : .milliseconds(500)
                try? await Task.sleep(for: delay)
            }
        }

        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                try? await Task.sleep(for: .milliseconds(400))
                print("[AppModel] didBecomeActive — \(permManager.permissionDiagnosticsSummary())")
                _ = await permManager.verifyScreenCaptureAccess(force: true)
                self?.refreshPermissionState(from: permManager)
            }
        }
    }

    private var hasAllPermissionsGranted: Bool {
        screenRecordingGranted && accessibilityGranted
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
    }

    private static func axPermissionNotificationStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            print("[AppModel] Registered DistributedNotificationCenter observer for com.apple.accessibility.api")
            let observer = center.addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { _ in
                print("[AppModel] Received com.apple.accessibility.api — scheduling refresh in 500 ms")
                continuation.yield()
            }
            continuation.onTermination = { _ in
                print("[AppModel] Removing DistributedNotificationCenter observer")
                center.removeObserver(observer)
            }
        }
    }

    // MARK: - Capture

    private func handleCaptureShortcutTrigger() {
        inspectSelectedTextForConversationTrigger(
            presentChatAfterSelection: false,
            onSelectionUnavailable: { [weak self] in
                self?.beginScreenshotCapture()
            }
        )
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

    func updateCaptureShortcut(_ shortcut: CaptureShortcut) {
        let normalizedShortcut = shortcut.normalized
        captureShortcut = normalizedShortcut
        hotkeyManager?.update(shortcut: normalizedShortcut)
        saveCaptureShortcut(normalizedShortcut)
        buildStatus = "Add-to-context shortcut updated to \(normalizedShortcut.displayString)."
        setCaptureErrorMessage(nil, source: .selectedText)
    }

    func clearContextStack() {
        cancelConversationSend(resetDraftState: false)
        contextSession?.clear()
        conversationCoordinator?.clearSession()
        overlayCoordinator?.hide()
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
        // Context (screenshots / selected text) is intentionally kept intact.
        if let conversation = savedConversations.first(where: { $0.id == mostRecent.id }) {
            buildStatus = "Loaded \(conversation.title) into the overlay."
        }
        syncOverlayState()
    }

    private func openMostRecentConversationChatIfAvailable() {
        guard let mostRecent = savedConversations.first else {
            return
        }

        conversationCoordinator?.resumeConversation(mostRecent.id)
        // syncOverlayState is called synchronously via the coordinator callback,
        // so viewModel.messages is populated before showChat runs.
        overlayCoordinator?.showChat(near: NSEvent.mouseLocation)
        buildStatus = "Resumed \"\(mostRecent.title)\"."
    }

    func handleAppDeactivationWhileContextVisible() {
        guard !isCaptureInProgress else {
            return
        }

        clearContextStack()
    }

    func dismissVisibleContextOverlayIfNeeded() {
        guard overlayCoordinator?.isVisible == true else {
            return
        }

        clearContextStack()
    }

    func showMainWindow() {
        if mainContentWindowController == nil {
            mainContentWindowController = MainContentWindowController(appModel: self)
        }

        mainContentWindowController?.showWindow()
    }

    func showSettingsInMainWindow() {
        selectedSection = .permissions
        showMainWindow()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
        hasCompletedOnboarding = true
    }

    func beginContextConversation() {
        guard hasContextItems else {
            // No context in the panel yet. Check whether text is currently selected in
            // the frontmost app WITHOUT attaching it — this avoids the ambiguous
            // onSelectionUnavailable callback firing for AX glitches.
            if contextSession?.hasCurrentlySelectedText() == true {
                // Text is selected: attach it and open a new conversation.
                inspectSelectedTextForConversationTrigger(
                    presentChatAfterSelection: true,
                    onSelectionUnavailable: { [weak self] in
                        // AX read succeeded in the pre-check but failed in the attach call
                        // (e.g. focus changed between the two calls). Keep the user on
                        // a fresh composer path instead of unexpectedly resuming the
                        // most recent saved conversation.
                        self?.openFreshContextConversationComposer()
                    },
                    onSelectionAlreadyAttached: { [weak self] in
                        // Same text is already in the current context, so this should
                        // still begin a fresh context-backed session rather than resume
                        // the last saved conversation.
                        self?.openFreshContextConversationComposer()
                    }
                )
            } else {
                // Nothing selected and no context: resume the most recent conversation.
                openMostRecentConversationChatIfAvailable()
            }
            return
        }

        inspectSelectedTextForConversationTrigger(
            presentChatAfterSelection: true,
            onSelectionUnavailable: { [weak self] in
                self?.openFreshContextConversationComposer()
            },
            onSelectionAlreadyAttached: { [weak self] in
                self?.openFreshContextConversationComposer()
            }
        )
    }

    private func inspectSelectedTextForConversationTrigger(
        presentChatAfterSelection: Bool,
        onSelectionUnavailable: @escaping @MainActor () -> Void = {},
        onSelectionAlreadyAttached: @escaping @MainActor () -> Void = {}
    ) {
        contextSession?.inspectSelectedTextForConversationTrigger(
            setStatus: { [weak self] status in
                self?.buildStatus = status
            },
            setError: { [weak self] message in
                self?.setCaptureErrorMessage(message, source: .selectedText)
            },
            onSelectionUnavailable: onSelectionUnavailable,
            onSelectionAlreadyAttached: onSelectionAlreadyAttached,
            onSelectionReady: { [weak self] in
                guard let self, !selectedTextContexts.isEmpty else {
                    return
                }

                syncOverlayState()

                if presentChatAfterSelection {
                    openFreshContextConversationComposer()
                } else {
                    overlayCoordinator?.showStack(near: NSEvent.mouseLocation)
                    buildStatus = "Selected text attached to the context window."
                }
            }
        )
    }

    private func openFreshContextConversationComposer() {
        conversationCoordinator?.clearSession()
        setCaptureErrorMessage(nil, source: .conversation)
        syncOverlayState()
        overlayCoordinator?.showChat(near: NSEvent.mouseLocation)
        buildStatus = "Context composer opened."
    }

    private func openContextConversationComposer() {
        syncOverlayState()
        overlayCoordinator?.showChat(near: NSEvent.mouseLocation)
        buildStatus = "Context composer opened."
    }

    func handleConversationSend(_ draft: String) {
        conversationCoordinator?.send(
            draft: draft,
            configuration: conversationConfiguration,
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
            }
        )
        contextSession?.clear()
        syncOverlayState()
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

    private func showContextStackNearCursor() {
        syncOverlayState()
        overlayCoordinator?.showStack(near: NSEvent.mouseLocation)
    }

    func resetCaptureShortcutToDefault() {
        updateCaptureShortcut(.defaultValue)
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

    func resetConversationConfiguration() {
        saveConversationConfiguration(.defaultValue)
        conversationConfiguration = .defaultValue
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
                providerDisplayName: conversationConfiguration.providerDisplayName,
                hasSavedConversations: !savedConversations.isEmpty,
                supportsWebSearch: conversationConfiguration.provider.supportsWebSearch,
                isWebSearchEnabled: conversationConfiguration.usesWebSearch
            )
        )
    }

    private func loadPersistedConversations() {
        conversationCoordinator?.loadPersistedConversations(onError: { [weak self] message in
            self?.setCaptureErrorMessage(message, source: .persistence)
        })
    }

    func clearDebugLog() {
        debugLogEntries.removeAll()
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
        syncOverlayState()
    }

    private func applyContextSnapshot(_ snapshot: ContextSession.Snapshot) {
        capturedScreenshots = snapshot.capturedScreenshots
        selectedTextContexts = snapshot.selectedTextContexts
        browserPageContexts = snapshot.browserPageContexts
        isCaptureInProgress = snapshot.isCaptureInProgress
        syncOverlayState()
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

        NSApp.mainMenu = mainMenu
    }
}

@MainActor
final class MainContentWindowController: NSWindowController {
    init(appModel: AppModel) {
        let hostingController = NSHostingController(rootView: ContentView().environment(appModel))
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Cue"
        window.setContentSize(NSSize(width: 960, height: 680))
        window.minSize = NSSize(width: 760, height: 520)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        guard let window else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
                .keyboardShortcut(.escape, modifiers: [])
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

struct ConversationSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var availableOllamaModels = OllamaModelCatalog.fallbackOptions
    @State private var isRefreshingOllamaModels = false
    @State private var ollamaModelsStatus: String?

    private let ollamaModelDiscoveryService = OllamaModelDiscoveryService()

    var body: some View {
        Section("Conversation") {
            Picker("Provider", selection: appState.conversationConfigurationBinding(for: \.provider)) {
                ForEach(ConversationProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            switch appState.conversationConfiguration.provider {
            case .ollama:
                TextField("http://localhost:11434", text: appState.conversationConfigurationBinding(for: \.ollamaBaseURL))
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: appState.conversationConfigurationBinding(for: \.ollamaModel)) {
                    ForEach(availableOllamaModels) { option in
                        Text(option.pickerTitle).tag(option.modelName)
                    }
                }

                HStack {
                    Button(isRefreshingOllamaModels ? "Refreshing..." : "Refresh Models") {
                        Task {
                            await refreshOllamaModels()
                        }
                    }
                    .disabled(isRefreshingOllamaModels)

                    Spacer()

                    Text(selectedOllamaModelOption.source == .installed ? "Installed via /api/tags" : "Curated fallback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch selectedOllamaModelOption.thinkingSupport {
                case .unsupported:
                    LabeledContent("Thinking", value: "Unavailable")
                case .toggle:
                    Toggle("Enable Thinking", isOn: ollamaThinkingToggleBinding)
                case let .levels(modes):
                    Picker("Thinking", selection: appState.conversationConfigurationBinding(for: \.ollamaThinkingMode)) {
                        ForEach(modes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Toggle("Use Web Search", isOn: appState.conversationConfigurationBinding(for: \.ollamaUseWebSearch))

                SecureField("Ollama API Key", text: appState.conversationConfigurationBinding(for: \.ollamaAPIKey))
                    .textFieldStyle(.roundedBorder)

                Text("When enabled, Ollama conversations may call hosted web search and fetch tools for current information. Provide an Ollama cloud API key here for the prototype, or leave it blank to fall back to `OLLAMA_API_KEY` from the app environment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Stored in UserDefaults for the prototype. Move this to Keychain before shipping.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(selectedOllamaModelOption.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(selectedOllamaModelOption.thinkingSupport.statusDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let ollamaModelsStatus {
                    Text(ollamaModelsStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .openAI:
                HStack {
                    TextField("gpt-5.4", text: appState.conversationConfigurationBinding(for: \.openAIModel))
                        .textFieldStyle(.roundedBorder)

                    Button("Reset to Default") {
                        appState.resetConversationConfiguration()
                    }
                }

                Toggle("Use Web Search", isOn: appState.conversationConfigurationBinding(for: \.openAIUseWebSearch))

                Text("When enabled, OpenAI conversations use the Responses API with the built-in web search tool for current information.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SecureField("OpenAI API Key", text: appState.conversationConfigurationBinding(for: \.openAIAPIKey))
                    .textFieldStyle(.roundedBorder)

                Text("Stored in UserDefaults for the prototype. Move this to Keychain before shipping.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

struct ShortcutSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var draftShortcut = CaptureShortcut.defaultValue

    var body: some View {
        Section("Shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(ShortcutFeatureCopy.openChatName, value: ShortcutFeatureCopy.openChatBinding)

                Text(ShortcutFeatureCopy.openChatSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent(ShortcutFeatureCopy.addToContextName, value: appState.captureShortcut.displayString)

                Text(ShortcutFeatureCopy.addToContextSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Customize Add To Context")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("Shortcut Type", selection: $draftShortcut.kind) {
                ForEach(CaptureShortcut.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            if draftShortcut.kind == .doubleModifier {
                Picker("Modifier", selection: doubleModifierRawValueBinding) {
                    ForEach(CaptureShortcut.doubleModifierOptions, id: \.rawValue) { modifier in
                        Text(modifierTitle(for: modifier)).tag(modifier.rawValue)
                    }
                }
            } else {
                Toggle("Shift", isOn: modifierBinding(.shift))
                Toggle("Option", isOn: modifierBinding(.option))
                Toggle("Control", isOn: modifierBinding(.control))
                Toggle("Command", isOn: modifierBinding(.command))
            }

            if draftShortcut.kind == .keyCombo {
                Picker("Key", selection: keyCodeBinding) {
                    ForEach(CaptureShortcut.availableKeys) { option in
                        Text(option.title).tag(option.keyCode)
                    }
                }
            }

            Button("Reset Add To Context To Default") {
                draftShortcut = .defaultValue
            }

            Text("Default is Double Option. If double-modifier detection feels unreliable on your machine, switch Add To Context to a held modifier combo or a key combination.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            draftShortcut = appState.captureShortcut
        }
        .onChange(of: draftShortcut, initial: false) { _, newValue in
            let normalizedShortcut = newValue.normalized
            if normalizedShortcut != newValue {
                draftShortcut = normalizedShortcut
                return
            }

            appState.updateCaptureShortcut(normalizedShortcut)
        }
    }

    private func modifierBinding(_ modifier: NSEvent.ModifierFlags) -> Binding<Bool> {
        Binding(
            get: {
                draftShortcut.contains(modifier)
            },
            set: { isEnabled in
                draftShortcut.setModifier(modifier, enabled: isEnabled)
            }
        )
    }

    private var doubleModifierRawValueBinding: Binding<UInt> {
        Binding(
            get: {
                CaptureShortcut.doubleModifierOptions.first(where: { draftShortcut.modifierFlags.contains($0) })?.rawValue ?? NSEvent.ModifierFlags.option.rawValue
            },
            set: { rawValue in
                draftShortcut.modifierFlagsRawValue = rawValue
            }
        )
    }

    private func modifierTitle(for modifier: NSEvent.ModifierFlags) -> String {
        switch modifier {
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        default:
            return "Modifier"
        }
    }

    private var keyCodeBinding: Binding<UInt16> {
        Binding(
            get: {
                draftShortcut.keyCode ?? CaptureShortcut.defaultKeyOption.keyCode
            },
            set: { keyCode in
                draftShortcut.keyCode = keyCode
            }
        )
    }
}


