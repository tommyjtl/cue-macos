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
            Distill the exchange into a concise note with a short topic title and a substantive body.
            Do not copy the user's first message verbatim as the title.
            Never return only a title line with an empty body.
            """
        )
    }

    static func attachmentContextMessages(from messages: [ConversationMessageDTO]) -> [ConversationMessageDTO] {
        guard let markMessage = messages.last(where: { message in
            guard message.role == .user,
                  !message.imageAttachments.isEmpty else {
                return false
            }

            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return MarkCommand.parse(from: trimmed) != nil
        }) else {
            return []
        }

        let noun = markMessage.imageAttachments.count == 1 ? "screenshot" : "screenshots"
        return [
            ConversationMessageDTO(
                id: markMessage.id,
                role: .user,
                text: "Attached \(noun) for this /mark conversation summary.",
                attachedContextLabels: markMessage.attachedContextLabels,
                imageAttachments: markMessage.imageAttachments
            )
        ]
    }

    static func normalizedTitle(
        parsedTitle: String,
        conversationMessages: [ConversationMessageDTO],
        userHint: String
    ) -> String {
        let trimmedTitle = parsedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return MarkExportModeResolver.conversationFallbackTitle(
                conversationMessages: conversationMessages,
                userHint: userHint
            )
        }

        if trimmedTitle.count > 80 {
            return topicTitle(from: conversationMessages, userHint: userHint)
        }

        if let firstUserMessage = MarkExportModeResolver.firstSubstantiveUserMessage(in: conversationMessages) {
            let firstUserText = firstUserMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle == firstUserText || (trimmedTitle.count > 48 && firstUserText.hasPrefix(trimmedTitle)) {
                return topicTitle(from: conversationMessages, userHint: userHint)
            }
        }

        return trimmedTitle
    }

    static func digestFallback(
        from conversationMessages: [ConversationMessageDTO],
        userHint: String
    ) -> String {
        let transcript = messagesForGeneration(from: conversationMessages)
        guard !transcript.isEmpty else {
            return ""
        }

        var parts: [String] = []

        if let firstUserMessage = transcript.first(where: { $0.role == .user }) {
            let question = flattened(firstUserMessage.text)
            if !question.isEmpty {
                parts.append("The user explored this with Cue: \(truncate(question, limit: 240))")
            }
        }

        let assistantMessages = transcript.filter { $0.role == .assistant }
        if assistantMessages.isEmpty {
            parts.append("## Highlights\n\n- Conversation saved from Cue for later reference.")
            return parts.joined(separator: "\n\n")
        }

        var highlightLines: [String] = []
        for message in assistantMessages {
            let text = flattened(message.text)
            guard !text.isEmpty else {
                continue
            }

            highlightLines.append(contentsOf: bulletCandidates(from: text))
        }

        if highlightLines.isEmpty {
            if let lastAssistant = assistantMessages.last {
                highlightLines.append(truncate(flattened(lastAssistant.text), limit: 1_200))
            }
        }

        let trimmedHint = userHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty {
            highlightLines.insert("Focus: \(trimmedHint)", at: 0)
        }

        let bullets = highlightLines
            .map { "- \($0)" }
            .joined(separator: "\n")
        parts.append("## Highlights\n\n\(bullets)")

        return parts.joined(separator: "\n\n")
    }

    private static func topicTitle(
        from conversationMessages: [ConversationMessageDTO],
        userHint: String
    ) -> String {
        let trimmedHint = userHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty {
            return String(trimmedHint.prefix(80))
        }

        if let firstUserMessage = MarkExportModeResolver.firstSubstantiveUserMessage(in: conversationMessages) {
            let firstSentence = firstSentence(from: firstUserMessage.text)
            if !firstSentence.isEmpty {
                return String(firstSentence.prefix(80))
            }
        }

        return MarkExportModeResolver.conversationFallbackTitle(
            conversationMessages: conversationMessages,
            userHint: userHint
        )
    }

    private static func bulletCandidates(from text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { flattened($0) }
            .filter { !$0.isEmpty }

        if paragraphs.count == 1 {
            let sentences = splitSentences(from: paragraphs[0])
            if sentences.count > 1 {
                return sentences.prefix(4).map { truncate($0, limit: 220) }
            }
        }

        return paragraphs.prefix(4).map { truncate($0, limit: 220) }
    }

    private static func splitSentences(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { sentence in
                if text.contains("\(sentence).") {
                    return "\(sentence)."
                }
                if text.contains("\(sentence)!") {
                    return "\(sentence)!"
                }
                if text.contains("\(sentence)?") {
                    return "\(sentence)?"
                }
                return sentence
            }
    }

    private static func firstSentence(from text: String) -> String {
        splitSentences(from: flattened(text)).first ?? ""
    }

    private static func flattened(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
