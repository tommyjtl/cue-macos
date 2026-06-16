import Foundation

struct SearchConfiguration: Codable, Equatable {
    var isAgentModeEnabled: Bool
    var sidecarBaseURL: String

    static let defaultValue = SearchConfiguration(
        isAgentModeEnabled: false,
        sidecarBaseURL: "http://127.0.0.1:8765"
    )

    init(isAgentModeEnabled: Bool, sidecarBaseURL: String = Self.defaultValue.sidecarBaseURL) {
        self.isAgentModeEnabled = isAgentModeEnabled
        self.sidecarBaseURL = sidecarBaseURL
    }

    var sidecarBaseURLValue: URL? {
        let trimmed = sidecarBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(string: trimmed)
    }

    func validationError(
        markConfiguration: MarkExportConfiguration,
        disabledMessage: String = "Enable Agent mode in Settings → Chat to use /search."
    ) -> String? {
        guard isAgentModeEnabled else {
            return disabledMessage
        }

        guard sidecarBaseURLValue != nil else {
            return "Enter a valid cue-search sidecar URL in Settings → Chat."
        }

        guard markConfiguration.isEnabled else {
            return "Enable \"Mark with /mark\" in Settings → Commands so Cue knows where your bookmarks live."
        }

        guard let folderURL = markConfiguration.exportFolderURL else {
            return "Choose a mark export folder in Settings → Commands."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return "The mark export folder does not exist."
        }

        return nil
    }
}
