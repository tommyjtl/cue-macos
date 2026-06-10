import Foundation

enum MarkExportMode: Equatable {
    case page(primaryPage: ConversationPageReferences.PageReference)
    case conversation

    var includesWebPageContext: Bool {
        switch self {
        case .page:
            true
        case .conversation:
            false
        }
    }
}

enum MarkExportModeResolver {
    static func resolve(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO],
        screenshotCount: Int,
        selectedTextContextCount: Int
    ) -> MarkExportMode? {
        if sessionBeganWithWebPage(
            browserPageContexts: browserPageContexts,
            conversationMessages: conversationMessages
        ) {
            guard let primaryPage = ConversationPageReferences.oldestPageReference(
                browserPageContexts: browserPageContexts,
                contextualMessages: contextualMessages,
                conversationMessages: conversationMessages
            ) else {
                return nil
            }

            return .page(primaryPage: primaryPage)
        }

        guard hasConversationMarkableContent(
            conversationMessages: conversationMessages,
            screenshotCount: screenshotCount,
            selectedTextContextCount: selectedTextContextCount
        ) else {
            return nil
        }

        return .conversation
    }

    static func sessionBeganWithWebPage(
        browserPageContexts: [BrowserPageContext],
        conversationMessages: [ConversationMessageDTO]
    ) -> Bool {
        if let firstUserMessage = firstSubstantiveUserMessage(in: conversationMessages) {
            return !firstUserMessage.attachedBrowserPages.isEmpty
        }

        return !browserPageContexts.isEmpty
    }

    static func hasConversationMarkableContent(
        conversationMessages: [ConversationMessageDTO],
        screenshotCount: Int,
        selectedTextContextCount: Int
    ) -> Bool {
        if MarkExportService.hasSubstantiveConversation(conversationMessages) {
            return true
        }

        return screenshotCount > 0 || selectedTextContextCount > 0
    }

    static func firstSubstantiveUserMessage(
        in messages: [ConversationMessageDTO]
    ) -> ConversationMessageDTO? {
        messages.first { message in
            guard message.role == .user else {
                return false
            }

            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }

            return ComposerCommandRegistry.parse(from: trimmed) == nil
        }
    }

    static func conversationFallbackTitle(
        conversationMessages: [ConversationMessageDTO],
        userHint: String
    ) -> String {
        let trimmedHint = userHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty {
            return String(trimmedHint.prefix(60))
        }

        if let firstUserMessage = firstSubstantiveUserMessage(in: conversationMessages) {
            let flattened = firstUserMessage.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !flattened.isEmpty {
                return String(flattened.prefix(60))
            }
        }

        return "Cue conversation"
    }
}
