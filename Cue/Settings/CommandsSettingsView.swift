import AppKit
import SwiftUI

struct CommandsSettingsView: View {
    var body: some View {
        SettingsDetailScaffold(title: "Commands") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SaveExportSettingsSection()
                MarkExportSettingsSection()
            }
        }
    }
}

// MARK: - Save

private struct SaveExportSettingsSection: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Save conversation")

            SettingsCard {
                SettingsToggleRow(
                    title: "Save with /save",
                    subtitle: "Type /save in the overlay composer to export the conversation as JSON.",
                    isOn: appState.saveExportConfigurationBinding(for: \.isEnabled)
                )

                if appState.saveExportConfiguration.isEnabled {
                    SettingsRowDivider()

                    SettingsRow(
                        title: "Default save location",
                        subtitle: defaultSaveLocationSubtitle
                    ) {
                        SettingsChangeButton("Choose…") {
                            chooseDefaultSaveFolder()
                        }
                    }

                    if let previewPath = appState.saveExportConfiguration.defaultSaveFolderURL?.path {
                        CommandExportFolderPathRow(
                            path: previewPath,
                            pathPattern: "Opens the save dialog here when you use /save (optional)."
                        )
                    }
                }
            }

            if appState.saveExportConfiguration.isEnabled {
                SettingsFootnote("Same JSON export as Recents → Export JSON. You pick the file each time in the save dialog.")
            }
        }
    }

    private var defaultSaveLocationSubtitle: String {
        if appState.saveExportConfiguration.defaultSaveFolderURL == nil {
            return "Optional folder shown first in the save dialog."
        }

        return "The save dialog opens in this folder by default."
    }

    private func chooseDefaultSaveFolder() {
        guard let url = runFolderPanel(
            message: "Choose a default folder for conversation JSON exports.",
            currentFolder: appState.saveExportConfiguration.defaultSaveFolderURL
        ) else { return }

        var configuration = appState.saveExportConfiguration
        configuration.defaultSaveFolderPath = url.path
        appState.updateSaveExportConfiguration(configuration)
    }
}

// MARK: - Mark

private struct MarkExportSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var pagePromptDraft = MarkExportPrompts.defaultBase
    @State private var conversationPromptDraft = MarkExportPrompts.conversationBase
    @State private var didLoadPromptDrafts = false
    @State private var pagePromptResetGeneration = 0
    @State private var conversationPromptResetGeneration = 0
    @State private var persistPagePromptTask: Task<Void, Never>?
    @State private var persistConversationPromptTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Mark")

            SettingsCard {
                SettingsToggleRow(
                    title: "Mark with /mark",
                    subtitle: "Type /mark or // to save a page bookmark or conversation summary.",
                    isOn: appState.markExportConfigurationBinding(for: \.isEnabled)
                )

                if appState.markExportConfiguration.isEnabled {
                    exportFolderSection(
                        configuration: appState.markExportConfiguration,
                        pathPattern: "Bookmarks are saved to {folder}/{yyyy-MM-dd}/{title}.md",
                        panelMessage: "Choose the folder where Cue should write mark exports."
                    ) {
                        chooseExportFolder()
                    }

                    systemPromptSection(
                        title: "Page bookmark prompt",
                        draft: $pagePromptDraft,
                        resetGeneration: pagePromptResetGeneration,
                        isDefault: isUsingDefaultPagePrompt,
                        onReset: resetPagePromptToPreset,
                        onDraftChange: schedulePersistPagePrompt
                    )

                    systemPromptSection(
                        title: "Conversation summary prompt",
                        draft: $conversationPromptDraft,
                        resetGeneration: conversationPromptResetGeneration,
                        isDefault: isUsingDefaultConversationPrompt,
                        onReset: resetConversationPromptToPreset,
                        onDraftChange: schedulePersistConversationPrompt
                    )
                }
            }

            if appState.markExportConfiguration.isEnabled {
                SettingsFootnote("Page mode bookmarks the oldest web page when the session started with one. Conversation mode summarizes chat when it started without a page. Type /mark or // at the start of the composer (// becomes /mark). Bookmarks are tagged cue in frontmatter.")
            }
        }
        .onAppear {
            loadPromptDraftsIfNeeded()
        }
        .onChange(of: appState.markExportConfiguration.systemPrompt) { _, newValue in
            if pagePromptDraft != newValue {
                pagePromptDraft = newValue
            }
        }
        .onChange(of: appState.markExportConfiguration.conversationSystemPrompt) { _, newValue in
            if conversationPromptDraft != newValue {
                conversationPromptDraft = newValue
            }
        }
        .onDisappear {
            persistPagePromptTask?.cancel()
            persistConversationPromptTask?.cancel()
            persistPagePromptIfNeeded(pagePromptDraft)
            persistConversationPromptIfNeeded(conversationPromptDraft)
        }
    }

    private var isUsingDefaultPagePrompt: Bool {
        MarkExportPrompts.isUsingDefaultPagePrompt(
            MarkExportConfiguration(
                isEnabled: appState.markExportConfiguration.isEnabled,
                exportFolderPath: appState.markExportConfiguration.exportFolderPath,
                systemPrompt: pagePromptDraft,
                conversationSystemPrompt: conversationPromptDraft
            )
        )
    }

    private var isUsingDefaultConversationPrompt: Bool {
        MarkExportPrompts.isUsingDefaultConversationPrompt(
            MarkExportConfiguration(
                isEnabled: appState.markExportConfiguration.isEnabled,
                exportFolderPath: appState.markExportConfiguration.exportFolderPath,
                systemPrompt: pagePromptDraft,
                conversationSystemPrompt: conversationPromptDraft
            )
        )
    }

    private func loadPromptDraftsIfNeeded() {
        guard !didLoadPromptDrafts else { return }
        pagePromptDraft = appState.markExportConfiguration.systemPrompt
        conversationPromptDraft = appState.markExportConfiguration.conversationSystemPrompt
        didLoadPromptDrafts = true
    }

    private func resetPagePromptToPreset() {
        persistPagePromptTask?.cancel()
        pagePromptDraft = MarkExportPrompts.defaultBase
        pagePromptResetGeneration += 1
        appState.resetMarkExportSystemPrompt()
    }

    private func resetConversationPromptToPreset() {
        persistConversationPromptTask?.cancel()
        conversationPromptDraft = MarkExportPrompts.conversationBase
        conversationPromptResetGeneration += 1
        appState.resetMarkExportConversationSystemPrompt()
    }

    private func schedulePersistPagePrompt(_ value: String) {
        persistPagePromptTask?.cancel()
        persistPagePromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persistPagePromptIfNeeded(value)
        }
    }

    private func schedulePersistConversationPrompt(_ value: String) {
        persistConversationPromptTask?.cancel()
        persistConversationPromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persistConversationPromptIfNeeded(value)
        }
    }

    private func persistPagePromptIfNeeded(_ value: String) {
        var configuration = appState.markExportConfiguration
        guard configuration.systemPrompt != value else { return }
        configuration.systemPrompt = value
        appState.updateMarkExportConfiguration(configuration)
    }

    private func persistConversationPromptIfNeeded(_ value: String) {
        var configuration = appState.markExportConfiguration
        guard configuration.conversationSystemPrompt != value else { return }
        configuration.conversationSystemPrompt = value
        appState.updateMarkExportConfiguration(configuration)
    }

    private func chooseExportFolder() {
        guard let url = runFolderPanel(
            message: "Choose the folder where Cue should write page bookmarks.",
            currentFolder: appState.markExportConfiguration.exportFolderURL
        ) else { return }

        var configuration = appState.markExportConfiguration
        configuration.exportFolderPath = url.path
        configuration.isEnabled = true
        appState.updateMarkExportConfiguration(configuration)
    }
}

// MARK: - Shared helpers

private func exportFolderSection(
    configuration: MarkExportConfiguration,
    pathPattern: String,
    panelMessage: String,
    chooseAction: @escaping () -> Void
) -> some View {
    exportFolderSection(
        folderURL: configuration.exportFolderURL,
        pathPattern: pathPattern,
        chooseAction: chooseAction
    )
}

private func exportFolderSection(
    folderURL: URL?,
    pathPattern: String,
    chooseAction: @escaping () -> Void
) -> some View {
    Group {
        SettingsRowDivider()

        SettingsRow(
            title: "Export folder",
            subtitle: folderURL == nil
                ? "Pick a folder inside your Obsidian vault or notes directory."
                : "New files are created under this folder, grouped by date."
        ) {
            SettingsChangeButton("Choose…", action: chooseAction)
        }

        if let previewPath = folderURL?.path {
            CommandExportFolderPathRow(path: previewPath, pathPattern: pathPattern)
        }
    }
}

private func systemPromptSection(
    title: String,
    draft: Binding<String>,
    resetGeneration: Int,
    isDefault: Bool,
    onReset: @escaping () -> Void,
    onDraftChange: @escaping (String) -> Void
) -> some View {
    Group {
        SettingsRowDivider()

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            SettingsMultilineTextEditor(
                text: draft,
                minHeight: 140,
                resetGeneration: resetGeneration
            )
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(
                SettingsLayout.insetBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onChange(of: draft.wrappedValue) { _, newValue in
                onDraftChange(newValue)
            }

            HStack {
                Text(isDefault ? "Using Cue preset" : "Using custom prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                SettingsChangeButton("Reset", action: onReset)
                    .disabled(isDefault)
            }
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func runFolderPanel(message: String, currentFolder: URL?) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Folder"
    panel.message = message
    panel.directoryURL = currentFolder

    guard panel.runModal() == .OK, let url = panel.url else {
        return nil
    }

    return url
}

private struct CommandExportFolderPathRow: View {
    let path: String
    let pathPattern: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pathPattern)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}
