import Foundation

struct MarkExportConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var exportFolderPath: String
    var systemPrompt: String
    var conversationSystemPrompt: String

    static let defaultValue = MarkExportConfiguration(
        isEnabled: false,
        exportFolderPath: "",
        systemPrompt: MarkExportPrompts.defaultBase,
        conversationSystemPrompt: MarkExportPrompts.conversationBase
    )

    init(
        isEnabled: Bool,
        exportFolderPath: String,
        systemPrompt: String = MarkExportPrompts.defaultBase,
        conversationSystemPrompt: String = MarkExportPrompts.conversationBase
    ) {
        self.isEnabled = isEnabled
        self.exportFolderPath = exportFolderPath
        self.systemPrompt = systemPrompt
        self.conversationSystemPrompt = conversationSystemPrompt
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case exportFolderPath
        case systemPrompt
        case conversationSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        exportFolderPath = try container.decode(String.self, forKey: .exportFolderPath)

        let prompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? MarkExportPrompts.defaultBase
        systemPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MarkExportPrompts.defaultBase
            : prompt

        let conversationPrompt = try container.decodeIfPresent(String.self, forKey: .conversationSystemPrompt)
            ?? MarkExportPrompts.conversationBase
        conversationSystemPrompt = conversationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MarkExportPrompts.conversationBase
            : conversationPrompt
    }

    var exportFolderURL: URL? {
        let trimmed = exportFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    var validationError: String? {
        validationError(enabledMessage: "Enable \"Mark pages with /mark\" in Settings → Commands.")
    }

    func validationError(enabledMessage: String) -> String? {
        guard isEnabled else {
            return enabledMessage
        }

        guard let folderURL = exportFolderURL else {
            return "Choose a mark export folder in Settings → Commands."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The mark export folder does not exist."
        }

        return nil
    }
}
