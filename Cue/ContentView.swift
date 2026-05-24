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
    @State private var showingSettings = false

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            AppSidebar(
                selectedSection: $appState.selectedSection,
                showingSettings: $showingSettings
            )

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
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
                .environment(appState)
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
        case .settings:
            CurrentSessionView()
        }
    }
}

private struct CurrentSessionView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConversationTranscriptPanel(
                    title: "Active Transcript",
                    subtitle: appState.conversationMessages.isEmpty
                        ? "Send a message from the overlay to start a conversation."
                        : "Live conversation state used by the overlay composer.",
                    messages: appState.conversationMessages
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConversationHistoryView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recents")
                    .font(.title2)
                    .fontWeight(.semibold)

                if appState.savedConversations.isEmpty {
                    Text("No saved conversations yet. Send a message from the overlay and Cue will persist the transcript here.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: selectionBinding) {
                        ForEach(appState.savedConversations) { conversation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.headline)
                                    .lineLimit(1)

                                Text(conversation.previewText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .tag(conversation.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 300, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)

            ConversationTranscriptPanel(
                title: selectedConversation?.title ?? "Conversation Preview",
                subtitle: selectedConversation == nil ? "Select a saved conversation to inspect it here." : selectedConversation?.updatedAt.formatted(date: .abbreviated, time: .shortened) ?? "",
                messages: selectedConversation?.messages ?? []
            )
        }
        .padding(28)
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

private struct DebugWorkspaceView: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Debug")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Runtime errors and fallback diagnostics collected from the current app session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Error Log")
                            .font(.headline)

                        Spacer()

                        Button("Clear Log") {
                            appState.clearDebugLog()
                        }
                        .disabled(appState.debugLogEntries.isEmpty)
                    }

                    if appState.debugLogEntries.isEmpty {
                        Text("No errors logged in this session yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                            .padding(18)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(appState.debugLogEntries) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(entry.source.rawValue)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.quaternary, in: Capsule())

                                        Spacer()

                                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(entry.message)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ConversationTranscriptPanel: View {
    let title: String
    let subtitle: String
    let messages: [ConversationMessageDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            if messages.isEmpty {
                Text("No messages yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .padding(18)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PermissionsSettingsSection: View {
    @Environment(AppModel.self) private var appState
    private let permissionManager = PermissionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PermissionItem.all) { item in
                PermissionStatusRow(
                    item: item,
                    isGranted: isGranted(item),
                    statusMessage: statusMessage(for: item),
                    onGrant: { grant(item) }
                )
            }

            if !permissionManager.isLikelyEligibleForScreenCaptureGrant {
                PermissionHelpCallout(
                    title: "Unsigned build — permissions cannot work",
                    message: permissionManager.unsignedBuildHint
                )
            } else if appState.needsRestartForPermissions {
                PermissionHelpCallout(
                    title: "Relaunch Cue to apply Screen Recording",
                    message: permissionManager.restartAfterPermissionChangeHint,
                    showsQuitButton: true
                )
            } else if permissionManager.hasStaleScreenCaptureGrant {
                PermissionHelpCallout(
                    title: "Stale Screen Recording permission",
                    message: permissionManager.staleScreenCaptureRecoveryHint
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
            return "Enable Accessibility for Cue.app in System Settings"
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
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsQuitButton {
                Button("Quit Cue") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PermissionStatusRow: View {
    let item: PermissionItem
    let isGranted: Bool
    let statusMessage: String
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(isGranted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Enable…", action: onGrant)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            isGranted ? AnyShapeStyle(.clear) : AnyShapeStyle(Color.orange.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
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
    @Binding var showingSettings: Bool

    private let primarySections: [AppModel.SidebarSection] = [.inbox, .recents]
    private let utilitySections: [AppModel.SidebarSection] = [.debug]

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

            // Primary navigation
            VStack(spacing: 1) {
                ForEach(primarySections) { section in
                    SidebarNavItem(section: section, selectedSection: $selectedSection)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Bottom utility
            VStack(spacing: 1) {
                Divider()
                    .padding(.bottom, 6)

                ForEach(utilitySections) { section in
                    SidebarNavItem(section: section, selectedSection: $selectedSection)
                }

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text("Settings")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
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

// MARK: - Settings Sheet

private struct SettingsSheetView: View {
    @Environment(AppModel.self) private var appState
    @State private var selectedCategory: SettingsCategory = .permissions

    private enum SettingsCategory: String, CaseIterable, Identifiable {
        case permissions, shortcuts, conversation

        var id: Self { self }

        var title: String {
            switch self {
            case .permissions: "Permissions"
            case .shortcuts: "Shortcuts"
            case .conversation: "Conversation"
            }
        }

        var icon: String {
            switch self {
            case .permissions: "lock.shield"
            case .shortcuts: "keyboard"
            case .conversation: "bubble.left.and.bubble.right"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left category list
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                VStack(spacing: 1) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsCategoryItem(
                            title: category.title,
                            icon: category.icon,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .frame(width: 196)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Right content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(selectedCategory.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    switch selectedCategory {
                    case .permissions:
                        PermissionsSettingsSection()
                    case .shortcuts:
                        ShortcutSettingsSection()
                    case .conversation:
                        ConversationSettingsSection()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 680, height: 480)
        .task {
            await appState.refreshPermissions()
        }
    }
}

private struct SettingsCategoryItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
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
