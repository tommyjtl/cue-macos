import Foundation
import SQLite3

final class DatabaseManager {
    private(set) var database: OpaquePointer?

    init(databaseURL: URL) throws {
        try CueStoragePaths.ensureParentDirectoryExists(for: databaseURL)
        try openDatabase(at: databaseURL)
    }

    deinit {
        sqlite3_close(database)
    }

    func bootstrapConversationStoreSchema() throws {
        try execute(sql: "PRAGMA foreign_keys = ON;")
        try execute(
            sql: """
            CREATE TABLE IF NOT EXISTS conversations (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              conversation_id TEXT NOT NULL,
              role TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'complete',
              created_at REAL NOT NULL,
              FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS message_parts (
              id TEXT PRIMARY KEY,
              message_id TEXT NOT NULL,
              type TEXT NOT NULL,
              sort_index INTEGER NOT NULL,
              text_content TEXT,
              created_at REAL NOT NULL,
              FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at
            ON messages(conversation_id, created_at);

            CREATE INDEX IF NOT EXISTS idx_message_parts_message_sort
            ON message_parts(message_id, sort_index);
            """
        )
    }

    private func openDatabase(at url: URL) throws {
        let result = sqlite3_open(url.path, &database)
        guard result == SQLITE_OK else {
            let message = databaseErrorMessage
            sqlite3_close(database)
            database = nil
            throw ConversationStoreError.databaseOpenFailed(message)
        }
    }

    private func execute(sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.statementExecutionFailed(databaseErrorMessage)
        }
    }

    private var databaseErrorMessage: String {
        guard let database, let pointer = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: pointer)
    }
}