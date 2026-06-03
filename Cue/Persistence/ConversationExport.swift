import AppKit
import Foundation
import UniformTypeIdentifiers

enum ConversationExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Cue could not encode the conversation export."
        }
    }
}

struct ExportedConversationAttachment: Encodable, Equatable, Sendable {
    enum Kind: String, Encodable, Sendable {
        case image
        case webPage
        case selectedText
    }

    let kind: Kind
    let path: String?
    let url: String?
    let text: String?

    nonisolated static func image(path: String) -> Self {
        Self(kind: .image, path: path, url: nil, text: nil)
    }

    nonisolated static func webPage(url: String) -> Self {
        Self(kind: .webPage, path: nil, url: url, text: nil)
    }

    nonisolated static func selectedText(_ text: String) -> Self {
        Self(kind: .selectedText, path: nil, url: nil, text: text)
    }
}

struct ExportedConversationMessage: Encodable, Equatable, Sendable {
    let id: UUID
    let role: String
    let text: String
    let attachments: [ExportedConversationAttachment]
}

struct ExportedConversationDocument: Encodable, Equatable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [ExportedConversationMessage]
}

enum ConversationExport {
    nonisolated static func makeDocument(from conversation: PersistedConversation) -> ExportedConversationDocument {
        ExportedConversationDocument(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messages: conversation.messages.map(exportedMessage(from:))
        )
    }

    nonisolated static func encode(_ conversation: PersistedConversation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(makeDocument(from: conversation)) else {
            throw ConversationExportError.encodingFailed
        }

        return data
    }

    nonisolated static func attachments(for message: ConversationMessageDTO) -> [ExportedConversationAttachment] {
        var attachments: [ExportedConversationAttachment] = []

        for image in message.imageAttachments {
            attachments.append(.image(path: absoluteImagePath(for: image)))
        }

        for page in message.attachedBrowserPages {
            attachments.append(.webPage(url: page.url))
        }

        for selectedText in message.attachedSelectedTexts {
            attachments.append(.selectedText(selectedText.text))
        }

        return attachments
    }

    nonisolated private static func exportedMessage(from message: ConversationMessageDTO) -> ExportedConversationMessage {
        ExportedConversationMessage(
            id: message.id,
            role: message.role.rawValue,
            text: message.text,
            attachments: attachments(for: message)
        )
    }

    nonisolated private static func absoluteImagePath(for reference: ConversationImageAttachmentReference) -> String {
        guard let rootDirectory = try? CueStoragePaths.conversationAttachmentsDirectory() else {
            return reference.relativePath
        }

        return rootDirectory
            .appendingPathComponent(reference.relativePath, isDirectory: false)
            .path
    }
}

@MainActor
enum ConversationExportPresenter {
    static func save(conversation: PersistedConversation) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = sanitizedFilename(for: conversation.title)

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            let data = try ConversationExport.encode(conversation)
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private static func sanitizedFilename(for title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let baseName = sanitized.isEmpty ? "conversation" : String(sanitized.prefix(80))
        return "\(baseName).json"
    }
}
