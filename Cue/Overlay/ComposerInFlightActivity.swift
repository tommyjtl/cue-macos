import Foundation

enum ComposerInFlightActivity: Equatable, Sendable {
    case none
    case exportingConversation
    case generatingBookmark

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
        case .generatingBookmark:
            "Cue is writing a markdown bookmark for this page."
        }
    }
}
