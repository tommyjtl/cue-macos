import Foundation

extension ContextItem {
    nonisolated init(screenshot: CapturedScreenshot) {
        self.init(
            id: screenshot.id,
            type: .screenshot,
            createdAt: screenshot.createdAt,
            previewTitle: screenshot.fileName,
            textContent: nil,
            localFilePath: screenshot.fileURL.path,
            mimeType: "image/png",
            sourceAppName: nil,
            sourceWindowTitle: nil
        )
    }

    nonisolated init(selectedTextSnapshot: AttachedTextContext, createdAt: Date = Date()) {
        self.init(
            id: UUID(),
            type: .selectedText,
            createdAt: createdAt,
            previewTitle: selectedTextSnapshot.appName ?? "Selected Text",
            textContent: selectedTextSnapshot.text,
            localFilePath: nil,
            mimeType: "text/plain",
            sourceAppName: selectedTextSnapshot.appName,
            sourceWindowTitle: nil
        )
    }
    nonisolated init(browserPageContext: BrowserPageContext) {
        self.init(
            id: browserPageContext.id,
            type: .webPage,
            createdAt: browserPageContext.createdAt,
            previewTitle: browserPageContext.pageTitle,
            textContent: browserPageContext.extractedText,
            localFilePath: nil,
            mimeType: "text/plain",
            sourceAppName: browserPageContext.browserName,
            sourceWindowTitle: browserPageContext.url
        )
    }
}

extension ContextStack {
    nonisolated init(screenshots: [CapturedScreenshot], selectedTextSnapshot: AttachedTextContext?) {
        let screenshotItems = screenshots.map { ContextItem(screenshot: $0) }
        let selectedTextItems = selectedTextSnapshot.map { [ContextItem(selectedTextSnapshot: $0)] } ?? []
        let items = screenshotItems + selectedTextItems
        let createdAt = items.map(\.createdAt).min() ?? Date()
        let updatedAt = items.map(\.createdAt).max() ?? createdAt

        self.init(items: items, createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension MessageRole {
    nonisolated init(_ role: ConversationMessageDTO.Role) {
        switch role {
        case .system:
            self = .system
        case .user:
            self = .user
        case .assistant:
            self = .assistant
        }
    }
}

extension ConversationMessageDTO.Role {
    nonisolated init(_ role: MessageRole) {
        switch role {
        case .system:
            self = .system
        case .user:
            self = .user
        case .assistant:
            self = .assistant
        }
    }
}

extension Message {
    nonisolated init(dto: ConversationMessageDTO, contextItems: [ContextItem] = [], status: MessageStatus = .complete) {
        var parts: [MessagePart] = []

        for (index, processBlock) in dto.processBlocks.enumerated() {
            parts.append(
                MessagePart(
                    type: Self.messagePartType(for: processBlock.kind),
                    sortIndex: index,
                    textContent: processBlock.text
                )
            )
        }

        let imageStartIndex = parts.count
        for (index, attachment) in dto.imageAttachments.enumerated() {
            parts.append(
                MessagePart(
                    type: .image,
                    sortIndex: imageStartIndex + index,
                    textContent: attachment.relativePath,
                    assetID: attachment.id
                )
            )
        }

        parts.append(MessagePart(type: .text, sortIndex: parts.count, textContent: dto.text))

        self.init(
            id: dto.id,
            role: MessageRole(dto.role),
            parts: parts,
            contextItems: contextItems,
            status: status,
            createdAt: Date()
        )
    }

    nonisolated var flattenedText: String {
        parts
            .sorted { $0.sortIndex < $1.sortIndex }
            .filter { $0.type == .text }
            .compactMap(\.textContent)
            .joined()
    }

    nonisolated var flattenedThinkingText: String? {
        let thinking = parts
            .sorted { $0.sortIndex < $1.sortIndex }
            .filter { $0.type == .thinking }
            .compactMap(\.textContent)
            .joined()

        let trimmed = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : thinking
    }

    nonisolated var orderedProcessBlocks: [ConversationProcessBlockDTO] {
        parts
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { part in
                guard let text = part.textContent,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                switch part.type {
                case .thinking:
                    return ConversationProcessBlockDTO(kind: .thinking, text: text)
                case .webSearch:
                    return ConversationProcessBlockDTO(kind: .webSearch, text: text)
                case .webFetch:
                    return ConversationProcessBlockDTO(kind: .webFetch, text: text)
                case .text, .image, .audio, .file:
                    return nil
                }
            }
    }

    private static nonisolated func messagePartType(for kind: ConversationProcessBlockDTO.Kind) -> MessagePartType {
        switch kind {
        case .thinking:
            return .thinking
        case .webSearch:
            return .webSearch
        case .webFetch:
            return .webFetch
        }
    }
}

extension ConversationMessageDTO {
    nonisolated init(message: Message) {
        let imageAttachments = message.parts
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { part -> ConversationImageAttachmentReference? in
                guard part.type == .image,
                      let relativePath = part.textContent,
                      let assetID = part.assetID else {
                    return nil
                }

                return ConversationImageAttachmentReference(
                    id: assetID,
                    mimeType: "image/png",
                    relativePath: relativePath
                )
            }

        self.init(
            id: message.id,
            role: ConversationMessageDTO.Role(message.role),
            text: message.flattenedText,
            processBlocks: message.orderedProcessBlocks,
            imageAttachments: imageAttachments
        )
    }
}

extension Conversation {
    nonisolated init(persistedConversation: PersistedConversation) {
        self.init(
            id: persistedConversation.id,
            title: persistedConversation.title,
            messages: persistedConversation.messages.map { Message(dto: $0) },
            createdAt: persistedConversation.createdAt,
            updatedAt: persistedConversation.updatedAt
        )
    }
}

extension PersistedConversation {
    nonisolated init(conversation: Conversation) {
        self.init(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messages: conversation.messages.map { ConversationMessageDTO(message: $0) }
        )
    }
}