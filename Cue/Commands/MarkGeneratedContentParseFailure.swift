import Foundation

enum MarkGeneratedContentParseFailure: Error, Equatable, CustomStringConvertible {
    case emptyResponse
    case invalidJSON(String)
    case emptyTitle
    case emptyBody

    var description: String {
        switch self {
        case .emptyResponse:
            return "Model returned an empty response."
        case let .invalidJSON(detail):
            return "JSON decode failed: \(detail)"
        case .emptyTitle:
            return "Parsed JSON had no title and no fallback was available."
        case .emptyBody:
            return "Parsed JSON body had no substantive content."
        }
    }
}
