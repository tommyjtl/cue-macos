import Foundation

struct AttachedTextContext: Equatable {
    let createdAt: Date
    let text: String
    let appName: String?
    let bundleIdentifier: String?

    func isEquivalent(to other: Self) -> Bool {
        text == other.text
            && appName == other.appName
            && bundleIdentifier == other.bundleIdentifier
    }
}
