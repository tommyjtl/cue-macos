import Foundation

enum MarkExportConversationTranscript {
    static func messagesForGeneration(from messages: [ConversationMessageDTO]) -> [ConversationMessageDTO] {
        messages.filter { message in
            guard message.role == .user || message.role == .assistant else {
                return false
            }

            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }

            if message.role == .user, ComposerCommandRegistry.parse(from: trimmed) != nil {
                return false
            }

            if message.role == .assistant, ObsidianSavedNoteMessage.savedNoteFileURL(from: trimmed) != nil {
                return false
            }

            return true
        }
    }

    static func generationContextMessage() -> ConversationMessageDTO {
        ConversationMessageDTO(
            role: .system,
            text: """
            The following user and assistant messages are the Cue conversation to summarize for this /mark export.
            Distill the exchange into the JSON note described in the system prompt.
            Include the user's questions in ## Why I saved this when they appear in the transcript.
            Do not copy the user's first message verbatim as the title.
            Never return an empty body.
            """
        )
    }

    static func generationRequestMessages(
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        userHint: String,
        includeTranscriptFraming: Bool = true
    ) -> [ConversationMessageDTO] {
        let transcriptMessages = messagesForGeneration(from: conversationMessages)
        var requestMessages = contextualMessages

        if includeTranscriptFraming, !transcriptMessages.isEmpty {
            requestMessages.append(generationContextMessage())
        }

        requestMessages.append(contentsOf: transcriptMessages)

        if let markTurnMessage = markTurnAttachmentMessage(
            from: conversationMessages,
            userHint: userHint
        ) {
            requestMessages.append(markTurnMessage)
        }

        return requestMessages
    }

    /// User message for the current /mark turn when it carries composer screenshots.
    /// The command text is excluded from the transcript, but attachments must stay on a user
    /// message with the same ID so OCR and raw-image delivery can resolve them.
    static func markTurnAttachmentMessage(
        from messages: [ConversationMessageDTO],
        userHint: String
    ) -> ConversationMessageDTO? {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return nil
        }

        let trimmedCommand = lastUserMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MarkCommand.parse(from: trimmedCommand) != nil else {
            return nil
        }

        guard !lastUserMessage.imageAttachments.isEmpty else {
            return nil
        }

        let displayText = userHint.trimmingCharacters(in: .whitespacesAndNewlines)

        return ConversationMessageDTO(
            id: lastUserMessage.id,
            role: .user,
            text: displayText,
            attachedContextLabels: lastUserMessage.attachedContextLabels,
            attachedBrowserPages: lastUserMessage.attachedBrowserPages,
            attachedSelectedTexts: lastUserMessage.attachedSelectedTexts,
            imageAttachments: lastUserMessage.imageAttachments
        )
    }
}
