import Foundation

enum CueStoragePathsError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Cue could not resolve its Application Support folder."
        }
    }
}

enum CueStoragePaths {
    static func cueRootDirectory() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CueStoragePathsError.applicationSupportUnavailable
        }

        return applicationSupportURL.appendingPathComponent("Cue", isDirectory: true)
    }

    static func databaseURL() throws -> URL {
        try cueRootDirectory().appendingPathComponent("cue.sqlite", isDirectory: false)
    }

    static func screenshotsDirectory() throws -> URL {
        try cueRootDirectory().appendingPathComponent("screenshots", isDirectory: true)
    }

    static func ensureParentDirectoryExists(for fileURL: URL) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        try ensureDirectoryExists(at: parentDirectory)
    }

    static func ensureDirectoryExists(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}