import Foundation

struct SaveExportConfiguration: Codable, Equatable {
    var isEnabled: Bool
    /// Optional default directory for the `/save` save dialog (not required).
    var defaultSaveFolderPath: String

    static let defaultValue = SaveExportConfiguration(
        isEnabled: false,
        defaultSaveFolderPath: ""
    )

    init(isEnabled: Bool, defaultSaveFolderPath: String = "") {
        self.isEnabled = isEnabled
        self.defaultSaveFolderPath = defaultSaveFolderPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        defaultSaveFolderPath = try container.decodeIfPresent(String.self, forKey: .defaultSaveFolderPath)
            ?? container.decodeIfPresent(String.self, forKey: .exportFolderPath)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(defaultSaveFolderPath, forKey: .defaultSaveFolderPath)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case defaultSaveFolderPath
        case exportFolderPath
    }

    var defaultSaveFolderURL: URL? {
        let trimmed = defaultSaveFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    func validationError(enabledMessage: String) -> String? {
        guard isEnabled else {
            return enabledMessage
        }

        return nil
    }
}

extension SaveExportConfiguration {
    var exportFolderPath: String {
        get { defaultSaveFolderPath }
        set { defaultSaveFolderPath = newValue }
    }

    var exportFolderURL: URL? { defaultSaveFolderURL }
}
