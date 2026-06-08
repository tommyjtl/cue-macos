import Foundation

enum ComposerInFlightActivity: Equatable, Sendable {
    case none
    case exportingConversation
    case generatingBookmark(preset: MarkExportDefaultSynthesisInstruction.PresetGeneratingContext?)

    var showsStatusBox: Bool {
        switch self {
        case .none:
            false
        case .exportingConversation, .generatingBookmark:
            true
        }
    }

    var title: String {
        switch self {
        case .none:
            ""
        case .exportingConversation:
            "Saving conversation"
        case .generatingBookmark:
            "Generating bookmark"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            ""
        case .exportingConversation:
            "Choose where to save the JSON export in the dialog."
        case let .generatingBookmark(preset):
            if preset != nil {
                "You didn't add a prompt — using a Cue preset for this bookmark."
            } else {
                "Cue is writing a markdown bookmark for this page."
            }
        }
    }

    var presetHint: String? {
        switch self {
        case let .generatingBookmark(preset?):
            preset.hint
        default:
            nil
        }
    }

    var presetScenarioLabel: String? {
        switch self {
        case let .generatingBookmark(preset?):
            preset.scenarioLabel
        default:
            nil
        }
    }
}
