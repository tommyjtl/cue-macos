import AppKit
import SwiftUI

struct ObsidianSettingsSection: View {
    @Environment(AppModel.self) private var appState
    @State private var noteSystemPromptDraft = ObsidianNotePrompts.defaultBase
    @State private var didLoadPromptDraft = false
    @State private var promptResetGeneration = 0
    @State private var persistPromptTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Obsidian Notes")

            SettingsCard {
                SettingsToggleRow(
                    title: "Save /note to Obsidian",
                    subtitle: "Type /note in the overlay composer to write a markdown note into your vault.",
                    isOn: appState.obsidianExportConfigurationBinding(for: \.isEnabled)
                )

                if appState.obsidianExportConfiguration.isEnabled {
                    SettingsRowDivider()

                    SettingsRow(
                        title: "Export folder",
                        subtitle: exportFolderSubtitle
                    ) {
                        SettingsChangeButton("Choose…") {
                            chooseExportFolder()
                        }
                    }

                    if let previewPath = appState.obsidianExportConfiguration.exportFolderURL?.path {
                        ObsidianExportFolderPathRow(path: previewPath)
                    }

                    SettingsRowDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Note system prompt")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        SettingsMultilineTextEditor(
                            text: $noteSystemPromptDraft,
                            minHeight: 140,
                            resetGeneration: promptResetGeneration
                        )
                            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                            .background(
                                SettingsLayout.insetBackground,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .onChange(of: noteSystemPromptDraft) { _, newValue in
                                schedulePersistPrompt(newValue)
                            }

                        HStack {
                            if isUsingDefaultPrompt {
                                Text("Using Cue preset")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Using custom prompt")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            SettingsChangeButton("Reset") {
                                resetPromptToPreset()
                            }
                            .disabled(isUsingDefaultPrompt)
                        }
                    }
                    .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if appState.obsidianExportConfiguration.isEnabled {
                SettingsFootnote("Use /note or /notes in chat to capture takeaways from the current conversation.")
            }
        }
        .onAppear {
            loadPromptDraftIfNeeded()
        }
        .onChange(of: appState.obsidianExportConfiguration.noteSystemPrompt) { _, newValue in
            if noteSystemPromptDraft != newValue {
                noteSystemPromptDraft = newValue
            }
        }
        .onDisappear {
            persistPromptTask?.cancel()
            persistPromptIfNeeded(noteSystemPromptDraft)
        }
    }

    private var isUsingDefaultPrompt: Bool {
        ObsidianNotePrompts.isUsingDefaultPrompt(
            ObsidianExportConfiguration(
                isEnabled: appState.obsidianExportConfiguration.isEnabled,
                exportFolderPath: appState.obsidianExportConfiguration.exportFolderPath,
                noteSystemPrompt: noteSystemPromptDraft
            )
        )
    }

    private var exportFolderSubtitle: String {
        if appState.obsidianExportConfiguration.exportFolderURL == nil {
            return "Pick a folder inside your Obsidian vault."
        }

        return "New notes are created under this folder, grouped by date."
    }

    private func loadPromptDraftIfNeeded() {
        guard !didLoadPromptDraft else {
            return
        }

        noteSystemPromptDraft = appState.obsidianExportConfiguration.noteSystemPrompt
        didLoadPromptDraft = true
    }

    private func resetPromptToPreset() {
        persistPromptTask?.cancel()

        let preset = ObsidianNotePrompts.defaultBase
        noteSystemPromptDraft = preset
        promptResetGeneration += 1
        appState.resetObsidianNoteSystemPrompt()
    }

    private func schedulePersistPrompt(_ value: String) {
        persistPromptTask?.cancel()
        persistPromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            persistPromptIfNeeded(value)
        }
    }

    private func persistPromptIfNeeded(_ value: String) {
        var configuration = appState.obsidianExportConfiguration
        guard configuration.noteSystemPrompt != value else {
            return
        }

        configuration.noteSystemPrompt = value
        appState.updateObsidianExportConfiguration(configuration)
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose the folder inside your Obsidian vault where Cue should write notes."

        if let currentFolder = appState.obsidianExportConfiguration.exportFolderURL {
            panel.directoryURL = currentFolder
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        var configuration = appState.obsidianExportConfiguration
        configuration.exportFolderPath = url.path
        configuration.isEnabled = true
        appState.updateObsidianExportConfiguration(configuration)
    }
}

private struct ObsidianExportFolderPathRow: View {
    let path: String

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

            Text("Notes are saved to {folder}/{yyyy-MM-dd}/{title}.md")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}
