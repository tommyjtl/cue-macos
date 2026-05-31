import AppKit
import SwiftUI

struct ObsidianSettingsSection: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Obsidian Notes")

            SettingsCard {
                SettingsToggleRow(
                    title: "Save /note to Obsidian",
                    subtitle: "Type /note in the overlay composer to write a markdown note into your vault.",
                    isOn: appState.obsidianExportConfigurationBinding(for: \.isEnabled)
                )

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
                    SettingsInsetContent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(previewPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Text("Notes are saved to {folder}/{yyyy-MM-dd}/{HH-mm - title}.md")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsFootnote("Use /note or /notes in chat to capture takeaways from the current conversation.")
        }
    }

    private var exportFolderSubtitle: String {
        if appState.obsidianExportConfiguration.exportFolderURL == nil {
            return "Pick a folder inside your Obsidian vault."
        }

        return "New notes are created under this folder, grouped by date."
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
