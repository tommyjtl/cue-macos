import Foundation
import SQLite3

struct PersistedConversation: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ConversationMessageDTO]

    var previewText: String {
        let candidate = messages
            .reversed()
            .first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .text
            ?? ""

        let flattened = candidate
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else {
            return "No messages yet"
        }

        return String(flattened.prefix(120))
    }
}

enum ConversationStoreError: LocalizedError {
    case applicationSupportUnavailable
    case databaseOpenFailed(String)
    case statementPreparationFailed(String)
    case statementExecutionFailed(String)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Cue could not resolve its Application Support folder for conversation history."
        case let .databaseOpenFailed(message):
            return "Cue could not open the conversation database: \(message)"
        case let .statementPreparationFailed(message):
            return "Cue could not prepare a conversation database query: \(message)"
        case let .statementExecutionFailed(message):
            return "Cue could not update conversation history: \(message)"
        case let .invalidData(message):
            return "Cue found invalid conversation data on disk: \(message)"
        }
    }
}

final class ConversationStore {
    private let databaseManager: DatabaseManager
    private let conversationRepository: ConversationRepository
    private let messageRepository: MessageRepository
    private var database: OpaquePointer? { databaseManager.database }

    convenience init() throws {
        try self.init(databaseURL: CueStoragePaths.databaseURL())
    }

    init(databaseURL: URL) throws {
        databaseManager = try DatabaseManager(databaseURL: databaseURL)
        conversationRepository = ConversationRepository(database: databaseManager.database)
        messageRepository = MessageRepository(database: databaseManager.database)
        try databaseManager.bootstrapConversationStoreSchema()
    }

    func loadConversations() throws -> [PersistedConversation] {
        var conversations: [PersistedConversation] = []
        for row in try conversationRepository.loadConversationRows() {
            let messages = try messageRepository.loadMessages(conversationID: row.id)

            conversations.append(
                PersistedConversation(
                    id: row.id,
                    title: row.title,
                    createdAt: row.createdAt,
                    updatedAt: row.updatedAt,
                    messages: messages
                )
            )
        }
        return conversations
    }

    func saveConversation(_ conversation: PersistedConversation) throws {
        try execute(sql: "BEGIN IMMEDIATE TRANSACTION;")

        do {
            try conversationRepository.upsertConversation(conversation)
            try messageRepository.deleteMessages(conversationID: conversation.id)

            for (index, message) in conversation.messages.enumerated() {
                try messageRepository.insertMessage(message, conversationID: conversation.id, sortIndex: index)
            }

            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
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