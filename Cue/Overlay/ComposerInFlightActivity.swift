import Foundation

enum ComposerInFlightActivity: Equatable, Sendable {
    case none
    case exportingConversation
    case generatingBookmark(
        preset: MarkExportDefaultSynthesisInstruction.PresetGeneratingContext?,
        mode: MarkExportMode
    )
    case searchingNotes

    var showsStatusBox: Bool {
        switch self {
        case .none:
            false
        case .exportingConversation, .generatingBookmark, .searchingNotes:
            true
        }
    }

    var title: String {
        switch self {
        case .none:
            ""
        case .exportingConversation:
            "Saving conversation"
        case let .generatingBookmark(_, mode):
            switch mode {
            case .page:
                "Generating bookmark"
            case .conversation:
                "Summarizing conversation"
            }
        case .searchingNotes:
            "Searching notes"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            ""
        case .exportingConversation:
            "Choose where to save the JSON export in the dialog."
        case let .generatingBookmark(preset, mode):
            if preset != nil {
                "You didn't add a prompt — using a Cue preset for this bookmark."
            } else {
                switch mode {
                case .page:
                    "Cue is writing a markdown bookmark for this page."
                case .conversation:
                    "Cue is writing a markdown summary of this conversation."
                }
            }
        case .searchingNotes:
            "Querying your saved bookmarks through cue-search."
        }
    }

    var presetHint: String? {
        switch self {
        case let .generatingBookmark(preset?, _):
            preset.hint
        default:
            nil
        }
    }

    var presetScenarioLabel: String? {
        switch self {
        case let .generatingBookmark(preset?, _):
            preset.scenarioLabel
        default:
            nil
        }
    }
}
