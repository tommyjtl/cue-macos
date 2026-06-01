//
//  ContentView.swift
//  CuePrototype
//
//  Created by Tommy Liu on 5/4/26.
//

import Observation
import SwiftUI
import Textual

struct ContentView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            AppSidebar(selectedSection: $appState.selectedSection)

            Divider()

            WorkspaceDetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: Binding(
            get: { !appState.hasCompletedOnboarding },
            set: { if !$0 { appState.completeOnboarding() } }
        )) {
            OnboardingView()
        }
        .task {
            appState.startBackgroundServicesIfNeeded()
        }
    }
}

private struct WorkspaceDetailView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        switch appState.selectedSection ?? .inbox {
        case .inbox:
            CurrentSessionView()
        case .recents:
            ConversationHistoryView()
        case .debug:
            DebugWorkspaceView()
        case .permissions:
            PermissionsSettingsView()
        case .general:
            GeneralSettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        SettingsDetailScaffold(title: "General") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SoundEffectsSettingsSection()
                ShortcutSettingsSection()
                ConversationSettingsSection()
                ObsidianSettingsSection()
            }
        }
    }
}

private struct PermissionsSettingsView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        SettingsDetailScaffold(
            title: "Permissions",
            subtitle: "Screen Recording and Accessibility are required for capture and global shortcuts."
        ) {
            PermissionsSettingsSection()
        }
        .task {
            await appState.refreshPermissions()
        }
    }
}

private struct CurrentSessionView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SettingsPageHeader(
                    title: "Sessions",
                    subtitle: "Live conversation state used by the overlay composer."
                )

                ConversationTranscriptPanel(
                    title: "Active Transcript",
                    subtitle: appState.conversationMessages.isEmpty
                        ? "Send a message from the overlay to start a conversation."
                        : nil,
                    messages: appState.conversationMessages
                )
            }
            .padding(SettingsLayout.pagePadding)
            .frame(maxWidth: SettingsLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ConversationHistoryView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsPageHeader(title: "Recents")

                Group {
                    if appState.savedConversations.isEmpty {
                        SettingsCard {
                            Text("No saved conversations yet. Send a message from the overlay and Cue will persist the transcript here.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(SettingsLayout.rowHorizontalPadding)
                                .padding(.vertical, SettingsLayout.rowVerticalPadding)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    } else {
                        List(selection: selectionBinding) {
                            ForEach(appState.savedConversations) { conversation in
                                RecentsConversationRow(conversation: conversation)
                                    .tag(conversation.id)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(
                            SettingsLayout.cardBackground,
                            in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 280, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)

            ConversationTranscriptPanel(
                title: selectedConversation?.title ?? "Conversation Preview",
                subtitle: selectedConversation == nil ? "Select a saved conversation to inspect it here." : selectedConversation?.updatedAt.formatted(date: .abbreviated, time: .shortened) ?? "",
                messages: selectedConversation?.messages ?? []
            )
        }
        .padding(SettingsLayout.pagePadding)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectedConversation: PersistedConversation? {
        guard let conversationID = appState.selectedSavedConversationID else {
            return nil
        }

        return appState.savedConversations.first(where: { $0.id == conversationID })
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { appState.selectedSavedConversationID },
            set: { appState.selectedSavedConversationID = $0 }
        )
    }
}

private struct RecentsConversationRow: View {
    let conversation: PersistedConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.system(size: 14, weight: .semibold))

            Text(conversation.previewText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct DebugWorkspaceView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SettingsPageHeader(
                    title: "Debug",
                    subtitle: "Session log for errors and clipboard attach diagnostics."
                )

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Log")
                                .font(.system(size: 15, weight: .semibold))

                            Spacer()

                            SettingsChangeButton("Clear") {
                                appState.clearDebugLog()
                            }
                            .disabled(appState.debugLogEntries.isEmpty)
                        }
                        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
                        .padding(.top, SettingsLayout.rowVerticalPadding)

                        if appState.debugLogEntries.isEmpty {
                            Text("No log entries in this session yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                                .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
                                .padding(.bottom, SettingsLayout.rowVerticalPadding)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(appState.debugLogEntries) { entry in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(entry.source.rawValue)
                                                .font(.system(size: 11, weight: .semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(SettingsLayout.insetBackground, in: Capsule())

                                            Spacer()

                                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(entry.message)
                                            .font(.system(size: 13))
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(SettingsLayout.insetBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
                            .padding(.bottom, SettingsLayout.rowVerticalPadding)
                        }
                    }
                }
            }
            .padding(SettingsLayout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ConversationTranscriptPanel: View {
    let title: String
    let subtitle: String?
    let messages: [ConversationMessageDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if messages.isEmpty {
                Text("No messages yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .padding(18)
                    .background(SettingsLayout.cardBackground, in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MainWindowConversationBubble(message: message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
                .background(SettingsLayout.cardBackground, in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PermissionsSettingsSection: View {
    @Environment(AppModel.self) private var appState
    private let permissionManager = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            SettingsCard {
                ForEach(Array(PermissionItem.all.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        SettingsRowDivider()
                    }

                    PermissionStatusRow(
                        item: item,
                        isGranted: isGranted(item),
                        statusMessage: statusMessage(for: item),
                        onGrant: { grant(item) }
                    )
                }
            }

            if !permissionManager.isLikelyEligibleForScreenCaptureGrant {
                PermissionHelpCallout(
                    title: "Unsigned build — permissions cannot work",
                    message: permissionManager.unsignedBuildHint
                )
            } else if appState.needsRestartForPermissions {
                PermissionHelpCallout(
                    title: permissionManager.restartAfterPermissionChangeTitle,
                    message: permissionManager.restartAfterPermissionChangeHint,
                    showsQuitButton: true
                )
            } else if permissionManager.hasStaleScreenCaptureGrant {
                PermissionHelpCallout(
                    title: "Stale Screen Recording permission",
                    message: permissionManager.staleScreenCaptureRecoveryHint
                )
            } else if appState.accessibilityGranted && !permissionManager.canReadOtherApplicationsAccessibilityTree() {
                PermissionHelpCallout(
                    title: "Accessibility cannot read other apps",
                    message: permissionManager.crossAppAccessibilityRecoveryHint
                )
            } else if !appState.screenRecordingGranted || !appState.accessibilityGranted {
                PermissionHelpCallout(
                    title: "Enable in System Settings",
                    message: permissionManager.enablePermissionsHint
                )
            }
        }
    }

    private func isGranted(_ item: PermissionItem) -> Bool {
        switch item.id {
        case .screenRecording: appState.screenRecordingGranted
        case .accessibility: appState.accessibilityGranted
        }
    }

    private func statusMessage(for item: PermissionItem) -> String {
        if isGranted(item) {
            return "Granted"
        }

        switch item.id {
        case .screenRecording:
            return "Enable Screen Recording for Cue.app, then relaunch Cue"
        case .accessibility:
            return "Enable Accessibility for Cue.app in System Settings, then relaunch Cue"
        }
    }

    private func grant(_ item: PermissionItem) {
        switch item.id {
        case .screenRecording:
            Task {
                await permissionManager.requestScreenCapturePermission()
                await appState.refreshPermissions()
            }
        case .accessibility:
            permissionManager.requestAccessibilityPermission()
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await appState.refreshPermissions()
            }
        }
    }
}

private struct PermissionHelpCallout: View {
    let title: String
    let message: String
    var showsQuitButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsQuitButton {
                SettingsChangeButton("Quit Cue") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous))
    }
}

private struct PermissionStatusRow: View {
    let item: PermissionItem
    let isGranted: Bool
    let statusMessage: String
    let onGrant: () -> Void

    var body: some View {
        SettingsRow(title: item.title, subtitle: statusMessage) {
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                SettingsChangeButton("Enable…", action: onGrant)
            }
        }
    }
}

private struct MainWindowConversationBubble: View {
    let message: ConversationMessageDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(senderLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(message.processBlocks) { block in
                processBlockView(for: block)
            }

            if message.role == .assistant, !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StructuredText(markdown: message.text)
                    .textual.structuredTextStyle(.default)
                    .textual.textSelection(.enabled)
            } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.text)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var senderLabel: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Cue"
        case .system:
            return "System"
        }
    }

    @ViewBuilder
    private func processBlockView(for block: ConversationProcessBlockDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(processBlockTitle(for: block))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(processBlockPreviewText(for: block))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func processBlockTitle(for block: ConversationProcessBlockDTO) -> String {
        switch block.kind {
        case .thinking:
            return "Thinking"
        case .webSearch:
            return "Web Search"
        case .webFetch:
            return "Web Fetch"
        }
    }

    private func processBlockPreviewText(for block: ConversationProcessBlockDTO) -> String {
        switch block.kind {
        case .thinking:
            let lines = block.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let previewLines = Array(lines.suffix(2))
            var preview = previewLines.joined(separator: "\n")
            if lines.count > 2 || !block.isComplete {
                preview += "..."
            }
            return preview
        case .webSearch, .webFetch:
            let lines = block.text.components(separatedBy: .newlines)
            return Array(lines.prefix(5)).joined(separator: "\n")
        }
    }
}

// MARK: - Custom Sidebar

private struct AppSidebar: View {
    @Binding var selectedSection: AppModel.SidebarSection?

    private let primarySections: [AppModel.SidebarSection] = [.inbox, .recents]
    private let settingsSections: [AppModel.SidebarSection] = [.permissions, .general]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App branding
            HStack(spacing: 8) {
                Image("MenuBarIcon")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Cue")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 14)

            VStack(spacing: 1) {
                ForEach(primarySections) { section in
                    SidebarNavItem(section: section, selectedSection: $selectedSection)
                }

                Divider()
                    .padding(.vertical, 8)

                Text("App Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                ForEach(settingsSections) { section in
                    SidebarNavItem(section: section, selectedSection: $selectedSection)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 1) {
                Divider()
                    .padding(.bottom, 6)

                SidebarNavItem(section: .debug, selectedSection: $selectedSection)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarNavItem: View {
    let section: AppModel.SidebarSection
    @Binding var selectedSection: AppModel.SidebarSection?
    @State private var isHovered = false

    private var isSelected: Bool { selectedSection == section }

    var body: some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (isHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.3) : .clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    ContentView()
    .environment(AppModel())
}
