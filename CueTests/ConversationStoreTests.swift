import Foundation
import Testing
@testable import Cue

@Suite("ConversationStore")
struct ConversationStoreTests {
    @Test("loads conversations after multiple save rounds")
    func loadsPersistedConversations() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-conversation-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let databaseURL = rootDirectory.appendingPathComponent("cue.sqlite")
        try CueStoragePaths.ensureDirectoryExists(at: rootDirectory)

        let store = try ConversationStore(databaseURL: databaseURL)

        for index in 0 ..< 3 {
            let conversationID = UUID()
            let message = ConversationMessageDTO(
                id: UUID(),
                role: .user,
                text: "Message \(index)"
            )
            try store.saveConversation(
                PersistedConversation(
                    id: conversationID,
                    title: "Conversation \(index)",
                    createdAt: Date(),
                    updatedAt: Date(),
                    messages: [message]
                )
            )
        }

        let loaded = try store.loadConversations()
        #expect(loaded.count == 3)
        #expect(loaded.allSatisfy { !$0.messages.isEmpty })
    }

    @Test("deletes a single message without affecting siblings")
    func deletesSingleMessage() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-conversation-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let databaseURL = rootDirectory.appendingPathComponent("cue.sqlite")
        try CueStoragePaths.ensureDirectoryExists(at: rootDirectory)

        let store = try ConversationStore(databaseURL: databaseURL)
        let conversationID = UUID()
        let firstMessage = ConversationMessageDTO(id: UUID(), role: .user, text: "First")
        let secondMessage = ConversationMessageDTO(id: UUID(), role: .assistant, text: "Second")

        try store.saveConversation(
            PersistedConversation(
                id: conversationID,
                title: "Conversation",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [firstMessage, secondMessage]
            )
        )

        try store.deleteMessage(
            id: firstMessage.id,
            from: PersistedConversation(
                id: conversationID,
                title: "Conversation",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [secondMessage]
            )
        )

        let loaded = try store.loadConversations()
        #expect(loaded.count == 1)
        #expect(loaded[0].messages.count == 1)
        #expect(loaded[0].messages[0].id == secondMessage.id)
        #expect(loaded[0].messages[0].text == "Second")
    }
}
