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
    @State private var systemPromptDraft = SaveExportPrompts.defaultBase
    @State private var didLoadPromptDraft = false
    @State private var promptResetGeneration = 0
    @State private var persistPromptTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Save conversation")

            SettingsCard {
                SettingsToggleRow(
                    title: "Save with /save",
                    subtitle: "Type /save in the overlay composer (or /note) to write a structured markdown note.",
                    isOn: appState.saveExportConfigurationBinding(for: \.isEnabled)
                )

                if appState.saveExportConfiguration.isEnabled {
                    exportFolderSection(
                        configuration: appState.saveExportConfiguration,
                        pathPattern: "Notes are saved to {folder}/{yyyy-MM-dd}/{title}.md",
                        panelMessage: "Choose the folder where Cue should write saved conversation notes."
                    ) {
                        chooseExportFolder()
                    }

                    systemPromptSection(
                        draft: $systemPromptDraft,
                        resetGeneration: promptResetGeneration,
                        isDefault: isUsingDefaultPrompt,
                        onReset: resetPromptToPreset,
                        onDraftChange: schedulePersistPrompt
                    )
                }
            }

            if appState.saveExportConfiguration.isEnabled {
                SettingsFootnote("Use /save, /note, or /notes in chat. Add a hint after the command to emphasize topics.")
            }
        }
        .onAppear { loadPromptDraftIfNeeded() }
        .onChange(of: appState.saveExportConfiguration.systemPrompt) { _, newValue in
            if systemPromptDraft != newValue {
                systemPromptDraft = newValue
            }
        }
        .onDisappear {
            persistPromptTask?.cancel()
            persistPromptIfNeeded(systemPromptDraft)
        }
    }

    private var isUsingDefaultPrompt: Bool {
        SaveExportPrompts.isUsingDefaultPrompt(
            SaveExportConfiguration(
                isEnabled: appState.saveExportConfiguration.isEnabled,
                exportFolderPath: appState.saveExportConfiguration.exportFolderPath,
                systemPrompt: systemPromptDraft
            )
        )
    }

    private func loadPromptDraftIfNeeded() {
        guard !didLoadPromptDraft else { return }
        systemPromptDraft = appState.saveExportConfiguration.systemPrompt
        didLoadPromptDraft = true
    }

    private func resetPromptToPreset() {
        persistPromptTask?.cancel()
        systemPromptDraft = SaveExportPrompts.defaultBase
        promptResetGeneration += 1
        appState.resetSaveExportSystemPrompt()
    }

    private func schedulePersistPrompt(_ value: String) {
        persistPromptTask?.cancel()
        persistPromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persistPromptIfNeeded(value)
        }
    }

    private func persistPromptIfNeeded(_ value: String) {
        var configuration = appState.saveExportConfiguration
        guard configuration.systemPrompt != value else { return }
        configuration.systemPrompt = value
        appState.updateSaveExportConfiguration(configuration)
    }

    private func chooseExportFolder() {
        guard let url = runFolderPanel(
            message: "Choose the folder where Cue should write saved conversation notes.",
            currentFolder: appState.saveExportConfiguration.exportFolderURL
        ) else { return }

        var configuration = appState.saveExportConfiguration
        configuration.exportFolderPath = url.path
        configuration.isEnabled = true
        appState.updateSaveExportConfiguration(configuration)
    }
}

// MARK: - Mark

private struct MarkExportSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var systemPromptDraft = MarkExportPrompts.defaultBase
    @State private var didLoadPromptDraft = false
    @State private var promptResetGeneration = 0
    @State private var persistPromptTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Mark page")

            SettingsCard {
                SettingsToggleRow(
                    title: "Mark with /mark",
                    subtitle: "Type /mark or // to bookmark the oldest page in the session with your angle.",
                    isOn: appState.markExportConfigurationBinding(for: \.isEnabled)
                )

                if appState.markExportConfiguration.isEnabled {
                    exportFolderSection(
                        configuration: appState.markExportConfiguration,
                        pathPattern: "Bookmarks are saved to {folder}/{yyyy-MM-dd}/{title}--{domain}.md",
                        panelMessage: "Choose the folder where Cue should write page bookmarks."
                    ) {
                        chooseExportFolder()
                    }

                    systemPromptSection(
                        draft: $systemPromptDraft,
                        resetGeneration: promptResetGeneration,
                        isDefault: isUsingDefaultPrompt,
                        onReset: resetPromptToPreset,
                        onDraftChange: schedulePersistPrompt
                    )
                }
            }

            if appState.markExportConfiguration.isEnabled {
                SettingsFootnote("Requires a web page in context. Use a hint after /mark or // (e.g. startup, blog, product).")
            }
        }
        .onAppear { loadPromptDraftIfNeeded() }
        .onChange(of: appState.markExportConfiguration.systemPrompt) { _, newValue in
            if systemPromptDraft != newValue {
                systemPromptDraft = newValue
            }
        }
        .onDisappear {
            persistPromptTask?.cancel()
            persistPromptIfNeeded(systemPromptDraft)
        }
    }

    private var isUsingDefaultPrompt: Bool {
        MarkExportPrompts.isUsingDefaultPrompt(
            MarkExportConfiguration(
                isEnabled: appState.markExportConfiguration.isEnabled,
                exportFolderPath: appState.markExportConfiguration.exportFolderPath,
                systemPrompt: systemPromptDraft
            )
        )
    }

    private func loadPromptDraftIfNeeded() {
        guard !didLoadPromptDraft else { return }
        systemPromptDraft = appState.markExportConfiguration.systemPrompt
        didLoadPromptDraft = true
    }

    private func resetPromptToPreset() {
        persistPromptTask?.cancel()
        systemPromptDraft = MarkExportPrompts.defaultBase
        promptResetGeneration += 1
        appState.resetMarkExportSystemPrompt()
    }

    private func schedulePersistPrompt(_ value: String) {
        persistPromptTask?.cancel()
        persistPromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            persistPromptIfNeeded(value)
        }
    }

    private func persistPromptIfNeeded(_ value: String) {
        var configuration = appState.markExportConfiguration
        guard configuration.systemPrompt != value else { return }
        configuration.systemPrompt = value
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
    configuration: SaveExportConfiguration,
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
    draft: Binding<String>,
    resetGeneration: Int,
    isDefault: Bool,
    onReset: @escaping () -> Void,
    onDraftChange: @escaping (String) -> Void
) -> some View {
    Group {
        SettingsRowDivider()

        VStack(alignment: .leading, spacing: 12) {
            Text("System prompt")
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
