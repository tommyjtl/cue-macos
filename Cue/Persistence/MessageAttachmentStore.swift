import Foundation

struct ConversationImageAttachmentReference: Identifiable, Equatable, Codable {
    let id: UUID
    let mimeType: String
    let relativePath: String

    func serialized() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MessageAttachmentStoreError.encodingFailed
        }
        return json
    }

    static func deserialized(from text: String) -> ConversationImageAttachmentReference? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ConversationImageAttachmentReference.self, from: data)
    }
}

enum MessageAttachmentStoreError: LocalizedError {
    case encodingFailed
    case fileUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Cue could not encode a message attachment reference."
        case let .fileUnavailable(path):
            return "Cue could not load a saved message attachment at \(path)."
        }
    }
}

struct MessageAttachmentStore {
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else if let defaultDirectory = try? CueStoragePaths.conversationAttachmentsDirectory() {
            self.rootDirectory = defaultDirectory
        } else {
            self.rootDirectory = FileManager.default.temporaryDirectory
        }
    }
    func saveImages(
        from screenshots: [CapturedScreenshot],
        conversationID: UUID,
        messageID: UUID
    ) throws -> [ConversationImageAttachmentReference] {
        try screenshots.map { screenshot in
            let attachmentID = screenshot.id
            let relativePath = "\(conversationID.uuidString)/\(messageID.uuidString)/\(attachmentID.uuidString).png"
            let destinationURL = try attachmentURL(relativePath: relativePath)
            try CueStoragePaths.ensureParentDirectoryExists(for: destinationURL)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: screenshot.fileURL, to: destinationURL)
            return ConversationImageAttachmentReference(
                id: attachmentID,
                mimeType: "image/png",
                relativePath: relativePath
            )
        }
    }

    func loadData(relativePath: String) throws -> Data {
        let fileURL = try attachmentURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MessageAttachmentStoreError.fileUnavailable(relativePath)
        }

        return try Data(contentsOf: fileURL)
    }

    func loadAttachmentDTOs(
        for references: [ConversationImageAttachmentReference]
    ) throws -> [ConversationImageAttachmentDTO] {
        try references.map { reference in
            ConversationImageAttachmentDTO(
                id: reference.id,
                mimeType: reference.mimeType,
                data: try loadData(relativePath: reference.relativePath)
            )
        }
    }

    func resolveMessageAttachments(
        for messages: [ConversationMessageDTO]
    ) throws -> [UUID: [ConversationImageAttachmentDTO]] {
        var resolved: [UUID: [ConversationImageAttachmentDTO]] = [:]

        for message in messages where message.role == .user && !message.imageAttachments.isEmpty {
            resolved[message.id] = try loadAttachmentDTOs(for: message.imageAttachments)
        }

        return resolved
    }

    private func attachmentURL(relativePath: String) throws -> URL {
        rootDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}
