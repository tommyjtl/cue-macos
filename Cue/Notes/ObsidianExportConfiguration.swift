import Foundation

struct ObsidianExportConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var exportFolderPath: String
    var noteSystemPrompt: String

    static let defaultValue = ObsidianExportConfiguration(
        isEnabled: false,
        exportFolderPath: "",
        noteSystemPrompt: ObsidianNotePrompts.defaultBase
    )

    init(
        isEnabled: Bool,
        exportFolderPath: String,
        noteSystemPrompt: String = ObsidianNotePrompts.defaultBase
    ) {
        self.isEnabled = isEnabled
        self.exportFolderPath = exportFolderPath
        self.noteSystemPrompt = noteSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        exportFolderPath = try container.decode(String.self, forKey: .exportFolderPath)
        noteSystemPrompt = try container.decodeIfPresent(String.self, forKey: .noteSystemPrompt)
            ?? ObsidianNotePrompts.defaultBase
        if noteSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteSystemPrompt = ObsidianNotePrompts.defaultBase
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case exportFolderPath
        case noteSystemPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(exportFolderPath, forKey: .exportFolderPath)
        try container.encode(noteSystemPrompt, forKey: .noteSystemPrompt)
    }

    var exportFolderURL: URL? {
        let trimmed = exportFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    var validationError: String? {
        guard isEnabled else {
            return "Enable \"Save /note to Obsidian\" in Settings."
        }

        guard let folderURL = exportFolderURL else {
            return "Choose an Obsidian export folder in Settings."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The Obsidian export folder does not exist."
        }

        return nil
    }
}
