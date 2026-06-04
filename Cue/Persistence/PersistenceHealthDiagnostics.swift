import Foundation
import SQLite3

enum PersistenceHealthDiagnostics {
    struct LaunchContext {
        var storeOpenError: String?
        var loadedConversationCount: Int
        var loadedMessageCount: Int
        var loadError: String?
    }

    static func launchReportLines(context: LaunchContext) -> [String] {
        var lines: [String] = ["Persistence health (launch)"]

        if let bundleID = Bundle.main.bundleIdentifier {
            lines.append("Bundle ID: \(bundleID)")
        }

        lines.append("App path: \(Bundle.main.bundleURL.path)")

        do {
            let root = try CueStoragePaths.cueRootDirectory()
            let databaseURL = try CueStoragePaths.databaseURL()
            let attachmentsURL = try CueStoragePaths.conversationAttachmentsDirectory()

            lines.append("Storage root: \(root.path)")
            lines.append("Database: \(databaseURL.path)")
            lines.append(databaseFileSummary(at: databaseURL))

            if let diskConversations = sqliteCount(
                at: databaseURL,
                sql: "SELECT COUNT(*) FROM conversations;"
            ) {
                lines.append("On-disk conversations: \(diskConversations)")
            } else {
                lines.append("On-disk conversations: unavailable (database not readable)")
            }

            if let diskMessages = sqliteCount(
                at: databaseURL,
                sql: "SELECT COUNT(*) FROM messages;"
            ) {
                lines.append("On-disk messages: \(diskMessages)")
            }

            lines.append(attachmentsDirectorySummary(at: attachmentsURL))
        } catch {
            lines.append("Storage paths: failed (\(error.localizedDescription))")
        }

        if let storeOpenError = context.storeOpenError {
            lines.append("ConversationStore: failed to open (\(storeOpenError))")
        } else {
            lines.append("ConversationStore: open")
        }

        if let loadError = context.loadError {
            lines.append("Load into Recents: failed (\(loadError))")
        } else {
            lines.append(
                "Load into Recents: \(context.loadedConversationCount) conversation(s), \(context.loadedMessageCount) message(s)"
            )
        }

        if context.storeOpenError == nil, let loadError = context.loadError {
            lines.append("Note: store opened but load failed — check schema or corrupt rows.")
        } else if context.storeOpenError != nil {
            lines.append("Note: saves and Recents are disabled until the store opens.")
        }

        return lines
    }

    private static func databaseFileSummary(at url: URL) -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return "Database file: missing"
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.formatted(date: .abbreviated, time: .standard)
            let modifiedSuffix = modified.map { " · modified \($0)" } ?? ""
            return "Database file: present · \(byteCount) bytes\(modifiedSuffix)"
        } catch {
            return "Database file: present (could not read attributes: \(error.localizedDescription))"
        }
    }

    private static func attachmentsDirectorySummary(at url: URL) -> String {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Attachments: directory missing"
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: url.path)
            let fileCount = contents.filter { !$0.hasPrefix(".") }.count
            return "Attachments: \(fileCount) file(s) in \(url.path)"
        } catch {
            return "Attachments: unreadable (\(error.localizedDescription))"
        }
    }

    private static func sqliteCount(at databaseURL: URL, sql: String) -> Int? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return Int(sqlite3_column_int(statement, 0))
    }
}
