import Foundation

enum ContextItemType: String, Codable, Equatable {
    case screenshot
    case clipboardText
    case clipboardImage
    case selectedText
    case fileURL
    case webPage
}

struct ContextItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ContextItemType
    let createdAt: Date
    var previewTitle: String?
    var textContent: String?
    var localFilePath: String?
    var mimeType: String?
    var sourceAppName: String?
    var sourceWindowTitle: String?
}

struct ContextStack: Identifiable, Codable, Equatable {
    let id: UUID
    var items: [ContextItem]
    let createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        items: [ContextItem],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum MessageRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

enum MessageStatus: String, Codable, Equatable {
    case streaming
    case complete
    case incomplete
    case failed
}

enum MessagePartType: String, Codable, Equatable {
    case thinking
    case webSearch = "web_search"
    case webFetch = "web_fetch"
    case text
    case image
    case audio
    case file
}

struct MessagePart: Identifiable, Codable, Equatable {
    let id: UUID
    let type: MessagePartType
    let sortIndex: Int
    var textContent: String?
    var assetID: UUID?
    var metadataJSON: String?

    nonisolated init(
        id: UUID = UUID(),
        type: MessagePartType,
        sortIndex: Int,
        textContent: String? = nil,
        assetID: UUID? = nil,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.type = type
        self.sortIndex = sortIndex
        self.textContent = textContent
        self.assetID = assetID
        self.metadataJSON = metadataJSON
    }
}

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    var parts: [MessagePart]
    var providerID: String?
    var modelID: String?
    var contextItems: [ContextItem]
    var status: MessageStatus
    let createdAt: Date

    nonisolated init(
        id: UUID = UUID(),
        role: MessageRole,
        parts: [MessagePart],
        providerID: String? = nil,
        modelID: String? = nil,
        contextItems: [ContextItem] = [],
        status: MessageStatus = .complete,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.providerID = providerID
        self.modelID = modelID
        self.contextItems = contextItems
        self.status = status
        self.createdAt = createdAt
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
}

enum AssetType: String, Codable, Equatable {
    case image
    case audio
    case file
}

struct Asset: Identifiable, Codable, Equatable {
    let id: UUID
    let type: AssetType
    let mimeType: String
    let localFilePath: String
    let createdAt: Date
    var previewTitle: String?
    var previewText: String?
    var byteSize: Int?
    var width: Int?
    var height: Int?
    var durationSeconds: Double?
    var sourceProvider: String?
}

enum PermissionKind: String, Codable, Equatable {
    case screenRecording
    case accessibility
}

struct InteractionErrorContext: Codable, Equatable {
    var message: String
    var permissionKind: PermissionKind?
    var conversationID: UUID?
}

enum InteractionState: Codable, Equatable {
    case idle
    case capturing
    case contextReady(ContextStack)
    case composing(ContextStack)
    case sending(conversationID: UUID)
    case viewingConversation(conversationID: UUID)
    case error(InteractionErrorContext)
}