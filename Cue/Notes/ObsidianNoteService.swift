import Foundation

enum ObsidianNoteServiceError: LocalizedError {
    case invalidModelResponse
    case missingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidModelResponse:
            return "Cue could not parse the generated note content."
        case let .missingConfiguration(message):
            return message
        }
    }
}

/// Legacy facade; new code should use `SaveExportService` directly.
struct ObsidianNoteService {
    typealias NoteReference = ConversationPageReferences.PageReference

    private let saveExportService: SaveExportService

    init(
        conversationService: ConversationService = ConversationService(),
        noteWriter: ObsidianNoteWriter = ObsidianNoteWriter()
    ) {
        self.saveExportService = SaveExportService(
            conversationService: conversationService,
            noteWriter: noteWriter
        )
    }

    func generateAndSave(
        userHint: String,
        configuration: ConversationConfiguration,
        obsidianConfiguration: SaveExportConfiguration,
        conversationMessages: [ConversationMessageDTO],
        contextualMessages: [ConversationMessageDTO],
        browserPageContexts: [BrowserPageContext],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        onDebugLog: ((String) -> Void)? = nil
    ) async throws -> ObsidianNoteWriter.WriteResult {
        try await saveExportService.generateAndSave(
            userHint: userHint,
            configuration: configuration,
            saveConfiguration: obsidianConfiguration,
            conversationMessages: conversationMessages,
            contextualMessages: contextualMessages,
            browserPageContexts: browserPageContexts,
            messageAttachments: messageAttachments,
            onDebugLog: onDebugLog
        )
    }

    static func collectReferences(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO]
    ) -> [NoteReference] {
        ConversationPageReferences.collectReferences(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: conversationMessages
        )
    }
}
