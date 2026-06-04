import Foundation

struct SaveExportConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var exportFolderPath: String
    var systemPrompt: String

    static let defaultValue = SaveExportConfiguration(
        isEnabled: false,
        exportFolderPath: "",
        systemPrompt: SaveExportPrompts.defaultBase
    )

    init(
        isEnabled: Bool,
        exportFolderPath: String,
        systemPrompt: String = SaveExportPrompts.defaultBase
    ) {
        self.isEnabled = isEnabled
        self.exportFolderPath = exportFolderPath
        self.systemPrompt = systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        exportFolderPath = try container.decode(String.self, forKey: .exportFolderPath)
        let prompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .noteSystemPrompt)
            ?? SaveExportPrompts.defaultBase
        systemPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SaveExportPrompts.defaultBase
            : prompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(exportFolderPath, forKey: .exportFolderPath)
        try container.encode(systemPrompt, forKey: .systemPrompt)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case exportFolderPath
        case systemPrompt
        case noteSystemPrompt
    }

    var exportFolderURL: URL? {
        let trimmed = exportFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    func validationError(enabledMessage: String) -> String? {
        guard isEnabled else {
            return enabledMessage
        }

        guard let folderURL = exportFolderURL else {
            return "Choose a save export folder in Settings → Commands."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The save export folder does not exist."
        }

        return nil
    }
}

extension SaveExportConfiguration {
    var noteSystemPrompt: String {
        get { systemPrompt }
        set { systemPrompt = newValue }
    }
}
