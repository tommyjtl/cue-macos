import Foundation

struct ObsidianExportConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var exportFolderPath: String

    static let defaultValue = ObsidianExportConfiguration(
        isEnabled: false,
        exportFolderPath: ""
    )

    var exportFolderURL: URL? {
        let trimmed = exportFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    var validationError: String? {
        guard isEnabled else {
            return nil
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
