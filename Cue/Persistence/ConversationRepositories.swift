import Foundation
import SQLite3

struct PersistedConversationRow {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

final class ConversationRepository {
    private let database: OpaquePointer?

    init(database: OpaquePointer?) {
        self.database = database
    }

    func loadConversationRows() throws -> [PersistedConversationRow] {
        let conversationsSQL = """
        SELECT id, title, created_at, updated_at
        FROM conversations
        ORDER BY updated_at DESC, created_at DESC;
        """

        let statement = try SQLiteRepositorySupport.prepareStatement(sql: conversationsSQL, database: database)
        defer { sqlite3_finalize(statement) }

        var rows: [PersistedConversationRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                PersistedConversationRow(
                    id: try SQLiteRepositorySupport.uuid(at: 0, in: statement),
                    title: SQLiteRepositorySupport.string(at: 1, in: statement) ?? "Untitled Conversation",
                    createdAt: SQLiteRepositorySupport.date(at: 2, in: statement),
                    updatedAt: SQLiteRepositorySupport.date(at: 3, in: statement)
                )
            )
        }

        try SQLiteRepositorySupport.finalizeStepResult(for: statement, database: database)
        return rows
    }

    func upsertConversation(_ conversation: PersistedConversation) throws {
        let sql = """
        INSERT INTO conversations (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            updated_at = excluded.updated_at;
        """

        let statement = try SQLiteRepositorySupport.prepareStatement(sql: sql, database: database)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, conversation.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, conversation.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, conversation.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, conversation.updatedAt.timeIntervalSince1970)

        try SQLiteRepositorySupport.executePreparedStatement(statement, database: database)
    }
}

final class MessageRepository {
    private let database: OpaquePointer?

    init(database: OpaquePointer?) {
        self.database = database
    }

    func loadMessages(conversationID: UUID) throws -> [ConversationMessageDTO] {
        let messagesSQL = """
                SELECT messages.id,
                             messages.role,
                             COALESCE(message_parts.type, 'text'),
                             COALESCE(message_parts.text_content, ''),
                             COALESCE(message_parts.sort_index, 0)
        FROM messages
        LEFT JOIN message_parts
                    ON message_parts.message_id = messages.id
        WHERE messages.conversation_id = ?
                ORDER BY messages.created_at ASC, message_parts.sort_index ASC;
        """

        let statement = try SQLiteRepositorySupport.prepareStatement(sql: messagesSQL, database: database)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, conversationID.uuidString, -1, SQLITE_TRANSIENT)

        var messages: [ConversationMessageDTO] = []
        var currentMessageID: UUID?
        var currentRole: ConversationMessageDTO.Role?
        var currentText = ""
        var currentProcessBlocks: [ConversationProcessBlockDTO] = []
        var currentImageAttachments: [ConversationImageAttachmentReference] = []

        func flushCurrentMessage() {
            guard let currentMessageID, let currentRole else {
                return
            }

            messages.append(
                ConversationMessageDTO(
                    id: currentMessageID,
                    role: currentRole,
                    text: currentText,
                    processBlocks: currentProcessBlocks,
                    imageAttachments: currentImageAttachments
                )
            )
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let messageID = try SQLiteRepositorySupport.uuid(at: 0, in: statement)
            let roleValue = SQLiteRepositorySupport.string(at: 1, in: statement) ?? ConversationMessageDTO.Role.assistant.rawValue
            guard let role = ConversationMessageDTO.Role(rawValue: roleValue) else {
                throw ConversationStoreError.invalidData("Unsupported message role '\(roleValue)'.")
            }

            if currentMessageID != messageID {
                flushCurrentMessage()
                currentMessageID = messageID
                currentRole = role
                currentText = ""
                currentProcessBlocks = []
                currentImageAttachments = []
            }

            let partType = SQLiteRepositorySupport.string(at: 2, in: statement) ?? "text"
            let partText = SQLiteRepositorySupport.string(at: 3, in: statement) ?? ""

            switch partType {
            case ConversationProcessBlockDTO.Kind.thinking.rawValue:
                currentProcessBlocks.append(ConversationProcessBlockDTO(kind: .thinking, text: partText))
            case ConversationProcessBlockDTO.Kind.webSearch.rawValue:
                currentProcessBlocks.append(ConversationProcessBlockDTO(kind: .webSearch, text: partText))
            case ConversationProcessBlockDTO.Kind.webFetch.rawValue:
                currentProcessBlocks.append(ConversationProcessBlockDTO(kind: .webFetch, text: partText))
            case "image":
                if let attachment = ConversationImageAttachmentReference.deserialized(from: partText) {
                    currentImageAttachments.append(attachment)
                }
            case "text":
                currentText += partText
            default:
                currentText += partText
            }
        }

        flushCurrentMessage()

        try SQLiteRepositorySupport.finalizeStepResult(for: statement, database: database)
        return messages
    }

    func deleteMessages(conversationID: UUID) throws {
        let sql = "DELETE FROM messages WHERE conversation_id = ?;"
        let statement = try SQLiteRepositorySupport.prepareStatement(sql: sql, database: database)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, conversationID.uuidString, -1, SQLITE_TRANSIENT)
        try SQLiteRepositorySupport.executePreparedStatement(statement, database: database)
    }

    func insertMessage(_ message: ConversationMessageDTO, conversationID: UUID, sortIndex: Int) throws {
        let messageSQL = """
        INSERT INTO messages (id, conversation_id, role, status, created_at)
        VALUES (?, ?, ?, 'complete', ?);
        """

        let messageStatement = try SQLiteRepositorySupport.prepareStatement(sql: messageSQL, database: database)
        defer { sqlite3_finalize(messageStatement) }

        sqlite3_bind_text(messageStatement, 1, message.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(messageStatement, 2, conversationID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(messageStatement, 3, message.role.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(messageStatement, 4, Date().timeIntervalSince1970 + Double(sortIndex) * 0.0001)
        try SQLiteRepositorySupport.executePreparedStatement(messageStatement, database: database)

        var partDefinitions: [(type: String, sortIndex: Int, text: String)] = message.processBlocks.enumerated().map { index, block in
            (type: block.kind.rawValue, sortIndex: index, text: block.text)
        }

        let imageStartIndex = partDefinitions.count
        partDefinitions.append(contentsOf: message.imageAttachments.enumerated().compactMap { index, attachment in
            guard let serialized = try? attachment.serialized() else {
                return nil
            }
            return (type: "image", sortIndex: imageStartIndex + index, text: serialized)
        })
        partDefinitions.append((type: "text", sortIndex: partDefinitions.count, text: message.text))

        let partSQL = """
        INSERT INTO message_parts (id, message_id, type, sort_index, text_content, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        for partDefinition in partDefinitions {
            let partStatement = try SQLiteRepositorySupport.prepareStatement(sql: partSQL, database: database)
            defer { sqlite3_finalize(partStatement) }

            sqlite3_bind_text(partStatement, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(partStatement, 2, message.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(partStatement, 3, partDefinition.type, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(partStatement, 4, Int64(partDefinition.sortIndex))
            sqlite3_bind_text(partStatement, 5, partDefinition.text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(partStatement, 6, Date().timeIntervalSince1970 + Double(sortIndex) * 0.0001)
            try SQLiteRepositorySupport.executePreparedStatement(partStatement, database: database)
        }
    }
}

private enum SQLiteRepositorySupport {
    static func prepareStatement(sql: String, database: OpaquePointer?) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.statementPreparationFailed(databaseErrorMessage(database: database))
        }
        return statement
    }

    static func executePreparedStatement(_ statement: OpaquePointer?, database: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw ConversationStoreError.statementExecutionFailed(databaseErrorMessage(database: database))
        }
    }

    static func finalizeStepResult(for statement: OpaquePointer?, database: OpaquePointer?) throws {
        let result = sqlite3_errcode(database)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.statementExecutionFailed(databaseErrorMessage(database: database))
        }
    }

    static func uuid(at index: Int32, in statement: OpaquePointer?) throws -> UUID {
        guard let value = string(at: index, in: statement), let uuid = UUID(uuidString: value) else {
            throw ConversationStoreError.invalidData("Expected a valid UUID value.")
        }

        return uuid
    }

    static func string(at index: Int32, in statement: OpaquePointer?) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }

        return String(cString: pointer)
    }

    static func date(at index: Int32, in statement: OpaquePointer?) -> Date {
        Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    static func databaseErrorMessage(database: OpaquePointer?) -> String {
        guard let database, let pointer = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }

        return String(cString: pointer)
    }
}