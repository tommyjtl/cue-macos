import Foundation

@MainActor
final class ConversationCoordinator {
    struct SessionSnapshot {
        var activeConversationID: UUID?
        var messages: [ConversationMessageDTO] = []
        var savedConversations: [PersistedConversation] = []
        var selectedSavedConversationID: UUID?
        var isConversationInProgress = false
        var inFlightActivity: ComposerInFlightActivity = .none
    }

    private let conversationService: ConversationService
    private let markExportService: MarkExportService
    private let conversationStore: ConversationStore?
    private let messageAttachmentStore: MessageAttachmentStore
    private let onSessionChange: @MainActor (SessionSnapshot) -> Void

    private var conversationTask: Task<Void, Never>?
    private var session = SessionSnapshot()

    init(
        conversationService: ConversationService? = nil,
        markExportService: MarkExportService? = nil,
        conversationStore: ConversationStore?,
        messageAttachmentStore: MessageAttachmentStore? = nil,
        onSessionChange: @escaping @MainActor (SessionSnapshot) -> Void
    ) {
        self.conversationService = conversationService ?? ConversationService()
        self.markExportService = markExportService ?? MarkExportService()
        self.conversationStore = conversationStore
        self.messageAttachmentStore = messageAttachmentStore ?? MessageAttachmentStore()
        self.onSessionChange = onSessionChange
        publishSession()
    }

    func loadPersistedConversations(onError: @MainActor (String) -> Void) {
        guard let conversationStore else {
            return
        }

        do {
            session.savedConversations = try conversationStore.loadConversations()
            if session.selectedSavedConversationID == nil {
                session.selectedSavedConversationID = session.savedConversations.first?.id
            }
            publishSession()
        } catch {
            onError(error.localizedDescription)
        }
    }

    func clearSession() {
        cancelTask()
        session.messages.removeAll()
        session.activeConversationID = nil
        session.isConversationInProgress = false
        session.inFlightActivity = .none
        publishSession()
    }

    func resumeConversation(_ conversationID: UUID) {
        guard let conversation = session.savedConversations.first(where: { $0.id == conversationID }) else {
            return
        }

        session.activeConversationID = conversation.id
        session.selectedSavedConversationID = conversation.id
        session.messages = conversation.messages
        publishSession()
    }

    func cancelSend(
        setError: @MainActor (String?) -> Void,
        syncPanel: @MainActor () -> Void
    ) {
        guard session.isConversationInProgress else {
            return
        }

        cancelTask()
        session.isConversationInProgress = false
        session.inFlightActivity = .none
        publishSession()
        setError(nil)
        syncPanel()
    }

    func send(
        draft: String,
        configuration: ConversationConfiguration,
        saveExportConfiguration: SaveExportConfiguration,
        markExportConfiguration: MarkExportConfiguration,
        screenshots: [CapturedScreenshot],
        selectedTextContexts: [AttachedTextContext],
        browserPageContexts: [BrowserPageContext],
        setStatus: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (String?) -> Void,
        syncPanel: @escaping @MainActor () -> Void,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            return
        }

        guard !session.isConversationInProgress else {
            return
        }

        if let parsedCommand = ComposerCommandRegistry.parse(from: trimmedDraft) {
            switch parsedCommand {
            case .save:
                sendSaveExport(
                    draft: trimmedDraft,
                    saveExportConfiguration: saveExportConfiguration,
                    screenshots: screenshots,
                    selectedTextContexts: selectedTextContexts,
                    browserPageContexts: browserPageContexts,
                    setStatus: setStatus,
                    setError: setError,
                    syncPanel: syncPanel
                )
            case let .mark(markCommand):
                sendMarkExport(
                    markCommand: markCommand,
                    draft: trimmedDraft,
                    configuration: configuration,
                    markExportConfiguration: markExportConfiguration,
                    screenshots: screenshots,
                    selectedTextContexts: selectedTextContexts,
                    browserPageContexts: browserPageContexts,
                    setStatus: setStatus,
                    setError: setError,
                    syncPanel: syncPanel,
                    onDebugLog: onDebugLog
                )
            }
            return
        }

        let contextLabels = attachedContextLabels(
            screenshots: screenshots,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts
        )

        let conversationID = ensureActiveConversationID()
        let userMessageID = UUID()

        let imageAttachments: [ConversationImageAttachmentReference]
        do {
            imageAttachments = try messageAttachmentStore.saveImages(
                from: screenshots,
                conversationID: conversationID,
                messageID: userMessageID
            )
        } catch {
            setError(error.localizedDescription)
            return
        }

        let userMessage = ConversationMessageDTO(
            id: userMessageID,
            role: .user,
            text: trimmedDraft,
            attachedContextLabels: contextLabels,
            attachedBrowserPages: browserPageContexts.map(\.attachedReference),
            attachedSelectedTexts: selectedTextContexts.map(AttachedSelectedTextReference.init(context:)),
            imageAttachments: imageAttachments
        )
        let requestMessages = ConversationContextMessages.build(
            sessionMessages: session.messages,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts
        ) + session.messages + [userMessage]
        let streamingAssistantMessageID = UUID()

        session.messages.append(userMessage)
        session.messages.append(
            ConversationMessageDTO(
                id: streamingAssistantMessageID,
                role: .assistant,
                text: "",
                thinkingText: nil,
                isThinkingComplete: false
            )
        )

        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        session.isConversationInProgress = true
        publishSession()
        setStatus("Sending request to \(configuration.providerDisplayName)...")
        setError(nil)
        syncPanel()

        cancelTask()
        conversationTask = Task { @MainActor in
            defer {
                conversationTask = nil
                session.isConversationInProgress = false
                publishSession()
                syncPanel()
            }

            do {
                let messageAttachments = try messageAttachmentStore.resolveMessageAttachments(for: requestMessages)
                let request = ConversationRequestDTO(
                    systemPrompt: conversationSystemPrompt(
                        for: configuration,
                        hasAttachments: !messageAttachments.isEmpty
                    ),
                    messages: requestMessages,
                    messageAttachments: messageAttachments
                )

                let response = try await conversationService.streamResponse(
                    request: request,
                    configuration: configuration,
                    onEvent: { [weak self] event in
                        await MainActor.run {
                            switch event {
                            case let .thinkingDelta(delta):
                                self?.appendAssistantThinkingDelta(
                                    delta,
                                    to: streamingAssistantMessageID,
                                    conversationID: conversationID,
                                    providerDisplayName: configuration.providerDisplayName,
                                    setStatus: setStatus,
                                    syncPanel: syncPanel,
                                    setError: setError
                                )
                            case .thinkingFinished:
                                self?.finishAssistantThinking(
                                    messageID: streamingAssistantMessageID,
                                    conversationID: conversationID,
                                    setError: setError,
                                    syncPanel: syncPanel
                                )
                            case let .toolResult(block):
                                self?.appendAssistantProcessBlock(
                                    block,
                                    to: streamingAssistantMessageID,
                                    conversationID: conversationID,
                                    setError: setError,
                                    syncPanel: syncPanel
                                )
                            case let .contentDelta(delta):
                                self?.appendAssistantDelta(
                                    delta,
                                    to: streamingAssistantMessageID,
                                    conversationID: conversationID,
                                    providerDisplayName: configuration.providerDisplayName,
                                    setStatus: setStatus,
                                    syncPanel: syncPanel,
                                    setError: setError
                                )
                            }
                        }
                    }
                )
                replaceMessage(id: streamingAssistantMessageID, with: response.message, conversationID: conversationID, setError: setError)

                setStatus("Received reply from \(configuration.providerDisplayName).")
            } catch is CancellationError {
                setStatus("Conversation cancelled.")
            } catch {
                let message = error.localizedDescription

                     if messageText(for: streamingAssistantMessageID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         thinkingText(for: streamingAssistantMessageID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    removeMessage(id: streamingAssistantMessageID, conversationID: conversationID, setError: setError)
                }

                session.messages.append(ConversationMessageDTO(role: .system, text: message))
                persistConversationSnapshot(conversationID: conversationID, setError: setError)
                publishSession()
                setError(message)
                setStatus("Conversation request failed.")
            }
        }
    }

    private func sendSaveExport(
        draft: String,
        saveExportConfiguration: SaveExportConfiguration,
        screenshots: [CapturedScreenshot],
        selectedTextContexts: [AttachedTextContext],
        browserPageContexts: [BrowserPageContext],
        setStatus: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (String?) -> Void,
        syncPanel: @escaping @MainActor () -> Void
    ) {
        let enabledMessage = "Enable \"Save with /save\" in Settings → Commands."
        if let validationError = saveExportConfiguration.validationError(enabledMessage: enabledMessage) {
            setError(validationError)
            setStatus("Save command is disabled.")
            return
        }

        guard SaveCommand.hasExportableContent(
            sessionMessages: session.messages,
            screenshotCount: screenshots.count,
            selectedTextContextCount: selectedTextContexts.count,
            browserPageContextCount: browserPageContexts.count
        ) else {
            setError("Send a message or attach context before using /save.")
            setStatus("Nothing to save yet.")
            return
        }

        let contextLabels = attachedContextLabels(
            screenshots: screenshots,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts
        )

        let conversationID = ensureActiveConversationID()
        let userMessageID = UUID()

        let imageAttachments: [ConversationImageAttachmentReference]
        do {
            imageAttachments = try messageAttachmentStore.saveImages(
                from: screenshots,
                conversationID: conversationID,
                messageID: userMessageID
            )
        } catch {
            setError(error.localizedDescription)
            return
        }

        let userMessage = ConversationMessageDTO(
            id: userMessageID,
            role: .user,
            text: draft,
            attachedContextLabels: contextLabels,
            attachedBrowserPages: browserPageContexts.map(\.attachedReference),
            attachedSelectedTexts: selectedTextContexts.map(AttachedSelectedTextReference.init(context:)),
            imageAttachments: imageAttachments
        )

        session.messages.append(userMessage)
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        session.inFlightActivity = .exportingConversation
        publishSession()
        setError(nil)
        syncPanel()

        let existingConversation = session.savedConversations.first(where: { $0.id == conversationID })
        let conversation = PersistedConversation(
            id: conversationID,
            title: conversationTitle(for: session.messages),
            createdAt: existingConversation?.createdAt ?? Date(),
            updatedAt: Date(),
            messages: session.messages
        )

        if let destinationURL = ConversationExportPresenter.save(
            conversation: conversation,
            defaultDirectoryURL: saveExportConfiguration.defaultSaveFolderURL
        ) {
            session.messages.append(
                ConversationMessageDTO(
                    role: .assistant,
                    text: ConversationJSONExportMessage.confirmationText(filePath: destinationURL.path)
                )
            )
            persistConversationSnapshot(conversationID: conversationID, setError: setError)
            publishSession()
            setStatus("Exported conversation JSON.")
        } else {
            setStatus("Export cancelled.")
        }

        session.inFlightActivity = .none
        publishSession()
        syncPanel()
    }

    private func sendMarkExport(
        markCommand: MarkCommand.Parsed,
        draft: String,
        configuration: ConversationConfiguration,
        markExportConfiguration: MarkExportConfiguration,
        screenshots: [CapturedScreenshot],
        selectedTextContexts: [AttachedTextContext],
        browserPageContexts: [BrowserPageContext],
        setStatus: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (String?) -> Void,
        syncPanel: @escaping @MainActor () -> Void,
        onDebugLog: ((String) -> Void)? = nil
    ) {
        if let validationError = markExportConfiguration.validationError {
            setError(validationError)
            setStatus("Mark export is not configured.")
            return
        }

        let contextualMessages = ConversationContextMessages.build(
            sessionMessages: session.messages,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts
        )

        guard MarkCommand.hasMarkablePage(
            browserPageContexts: browserPageContexts,
            contextualMessages: contextualMessages,
            conversationMessages: session.messages
        ) else {
            setError("Attach a web page before using /mark or //.")
            setStatus("No page to mark yet.")
            return
        }

        let contextLabels = attachedContextLabels(
            screenshots: screenshots,
            selectedTextContexts: selectedTextContexts,
            browserPageContexts: browserPageContexts
        )

        let conversationID = ensureActiveConversationID()
        let userMessageID = UUID()

        let imageAttachments: [ConversationImageAttachmentReference]
        do {
            imageAttachments = try messageAttachmentStore.saveImages(
                from: screenshots,
                conversationID: conversationID,
                messageID: userMessageID
            )
        } catch {
            setError(error.localizedDescription)
            return
        }

        let userMessage = ConversationMessageDTO(
            id: userMessageID,
            role: .user,
            text: draft,
            attachedContextLabels: contextLabels,
            attachedBrowserPages: browserPageContexts.map(\.attachedReference),
            attachedSelectedTexts: selectedTextContexts.map(AttachedSelectedTextReference.init(context:)),
            imageAttachments: imageAttachments
        )

        session.messages.append(userMessage)
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        session.isConversationInProgress = true
        session.inFlightActivity = .generatingBookmark
        publishSession()
        setStatus("Writing bookmark with \(configuration.providerDisplayName)...")
        setError(nil)
        syncPanel()

        let conversationMessages = session.messages

        cancelTask()
        conversationTask = Task { @MainActor in
            defer {
                conversationTask = nil
                session.isConversationInProgress = false
                session.inFlightActivity = .none
                publishSession()
                syncPanel()
            }

            do {
                let messageAttachments = try messageAttachmentStore.resolveMessageAttachments(for: conversationMessages)
                let result = try await markExportService.generateAndSave(
                    userHint: markCommand.userHint,
                    configuration: configuration,
                    markConfiguration: markExportConfiguration,
                    conversationMessages: conversationMessages,
                    contextualMessages: contextualMessages,
                    browserPageContexts: browserPageContexts,
                    messageAttachments: messageAttachments,
                    onDebugLog: onDebugLog
                )

                session.messages.append(
                    ConversationMessageDTO(
                        role: .assistant,
                        text: ObsidianSavedNoteMessage.confirmationText(filePath: result.fileURL.path)
                    )
                )
                persistConversationSnapshot(conversationID: conversationID, setError: setError)
                publishSession()
                setStatus("Saved bookmark \"\(result.title)\".")
            } catch is CancellationError {
                setStatus("Mark export cancelled.")
            } catch {
                let message = error.localizedDescription
                session.messages.append(ConversationMessageDTO(role: .system, text: message))
                persistConversationSnapshot(conversationID: conversationID, setError: setError)
                publishSession()
                setError(message)
                setStatus("Mark export failed.")
            }
        }
    }

    private func cancelTask() {
        conversationTask?.cancel()
        conversationTask = nil
    }

    private func publishSession() {
        onSessionChange(session)
    }

    private func attachedContextLabels(
        screenshots: [CapturedScreenshot],
        selectedTextContexts: [AttachedTextContext],
        browserPageContexts: [BrowserPageContext]
    ) -> [String] {
        var labels: [String] = []
        if screenshots.count == 1 {
            labels.append("Screenshot")
        } else if screenshots.count > 1 {
            labels.append("\(screenshots.count) Screenshots")
        }
        labels.append(contentsOf: selectedTextContexts.map { snapshot in
            snapshot.appName.map { "Text from \($0)" } ?? "Selected Text"
        })
        labels.append(contentsOf: browserPageContexts.map { page in
            browserPageContextLabel(page)
        })
        return labels
    }

    private func browserPageContextLabel(_ page: BrowserPageContext) -> String {
        let title = page.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return page.displayDomain
        }
        return title
    }

    private func appendAssistantDelta(
        _ delta: String,
        to messageID: UUID,
        conversationID: UUID,
        providerDisplayName: String,
        setStatus: @MainActor (String) -> Void,
        syncPanel: @MainActor () -> Void,
        setError: @MainActor (String?) -> Void
    ) {
        guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let existingMessage = session.messages[index]
        session.messages[index] = ConversationMessageDTO(
            id: existingMessage.id,
            role: existingMessage.role,
            text: existingMessage.text + delta,
            processBlocks: existingMessage.processBlocks,
            attachedContextLabels: existingMessage.attachedContextLabels,
            attachedBrowserPages: existingMessage.attachedBrowserPages,
            attachedSelectedTexts: existingMessage.attachedSelectedTexts,
            imageAttachments: existingMessage.imageAttachments
        )
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
        setStatus("Streaming reply from \(providerDisplayName)...")
        syncPanel()
    }

    private func appendAssistantThinkingDelta(
        _ delta: String,
        to messageID: UUID,
        conversationID: UUID,
        providerDisplayName: String,
        setStatus: @MainActor (String) -> Void,
        syncPanel: @MainActor () -> Void,
        setError: @MainActor (String?) -> Void
    ) {
        guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let existingMessage = session.messages[index]
        var updatedProcessBlocks = existingMessage.processBlocks

        if let lastIndex = updatedProcessBlocks.lastIndex(where: { $0.kind == .thinking && !$0.isComplete }) {
            let currentBlock = updatedProcessBlocks[lastIndex]
            updatedProcessBlocks[lastIndex] = ConversationProcessBlockDTO(
                id: currentBlock.id,
                kind: .thinking,
                text: currentBlock.text + delta,
                isComplete: false
            )
        } else {
            updatedProcessBlocks.append(ConversationProcessBlockDTO(kind: .thinking, text: delta, isComplete: false))
        }

        session.messages[index] = ConversationMessageDTO(
            id: existingMessage.id,
            role: existingMessage.role,
            text: existingMessage.text,
            processBlocks: updatedProcessBlocks,
            attachedContextLabels: existingMessage.attachedContextLabels,
            attachedBrowserPages: existingMessage.attachedBrowserPages,
            attachedSelectedTexts: existingMessage.attachedSelectedTexts,
            imageAttachments: existingMessage.imageAttachments
        )
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
        setStatus("Thinking with \(providerDisplayName)...")
        syncPanel()
    }

    private func finishAssistantThinking(
        messageID: UUID,
        conversationID: UUID,
        setError: @MainActor (String?) -> Void,
        syncPanel: @MainActor () -> Void
    ) {
        guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let existingMessage = session.messages[index]
        guard let lastIndex = existingMessage.processBlocks.lastIndex(where: { $0.kind == .thinking && !$0.isComplete }) else {
            return
        }

        var updatedProcessBlocks = existingMessage.processBlocks
        let currentBlock = updatedProcessBlocks[lastIndex]
        updatedProcessBlocks[lastIndex] = ConversationProcessBlockDTO(
            id: currentBlock.id,
            kind: .thinking,
            text: currentBlock.text,
            isComplete: true
        )

        session.messages[index] = ConversationMessageDTO(
            id: existingMessage.id,
            role: existingMessage.role,
            text: existingMessage.text,
            processBlocks: updatedProcessBlocks,
            attachedContextLabels: existingMessage.attachedContextLabels,
            attachedBrowserPages: existingMessage.attachedBrowserPages,
            attachedSelectedTexts: existingMessage.attachedSelectedTexts,
            imageAttachments: existingMessage.imageAttachments
        )
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
        syncPanel()
    }

    private func appendAssistantProcessBlock(
        _ block: ConversationProcessBlockDTO,
        to messageID: UUID,
        conversationID: UUID,
        setError: @MainActor (String?) -> Void,
        syncPanel: @MainActor () -> Void
    ) {
        guard let index = session.messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let existingMessage = session.messages[index]
        session.messages[index] = ConversationMessageDTO(
            id: existingMessage.id,
            role: existingMessage.role,
            text: existingMessage.text,
            processBlocks: existingMessage.processBlocks + [block],
            attachedContextLabels: existingMessage.attachedContextLabels,
            attachedBrowserPages: existingMessage.attachedBrowserPages,
            attachedSelectedTexts: existingMessage.attachedSelectedTexts,
            imageAttachments: existingMessage.imageAttachments
        )
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
        syncPanel()
    }

    private func replaceMessage(
        id: UUID,
        with message: ConversationMessageDTO,
        conversationID: UUID,
        setError: @MainActor (String?) -> Void
    ) {
        if let index = session.messages.firstIndex(where: { $0.id == id }) {
            session.messages[index] = ConversationMessageDTO(
                id: id,
                role: message.role,
                text: message.text,
                processBlocks: message.processBlocks,
                attachedContextLabels: session.messages[index].attachedContextLabels,
                attachedBrowserPages: session.messages[index].attachedBrowserPages,
                attachedSelectedTexts: session.messages[index].attachedSelectedTexts,
                imageAttachments: session.messages[index].imageAttachments
            )
        } else {
            session.messages.append(message)
        }

        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
    }

    private func removeMessage(
        id: UUID,
        conversationID: UUID,
        setError: @MainActor (String?) -> Void
    ) {
        session.messages.removeAll(where: { $0.id == id })
        persistConversationSnapshot(conversationID: conversationID, setError: setError)
        publishSession()
    }

    private func messageText(for messageID: UUID) -> String {
        session.messages.first(where: { $0.id == messageID })?.text ?? ""
    }

    private func thinkingText(for messageID: UUID) -> String {
        session.messages.first(where: { $0.id == messageID })?.thinkingText ?? ""
    }

    private func conversationSystemPrompt(
        for configuration: ConversationConfiguration,
        hasAttachments: Bool
    ) -> String {
        var prompt = """
        You are Cue, a concise assistant helping the user reason about their context.
        Use the attached context as the primary source when it is present.
        Reply in 4-5 sentences maximum. Give the direct answer first.
        Bullet points are fine when listing steps or options — keep each bullet to one line.
        Do not use headers. Do not write summaries or conclusions. Do not pad the response.
        You may use at most one analogy if it genuinely aids understanding, but only if the concept truly needs it.
        If the answer is simple, one sentence is ideal.
        """

        if configuration.usesWebSearch {
            prompt += """

            Web search and web fetch tools are available for this conversation.
            Use them proactively when the user's question is about something shown in a screenshot that likely needs outside context to identify, verify, or locate.
            This especially includes screenshots of web pages, social profiles, products, brands, places, news, or UI copied from the public web.
            If a screenshot-based question is likely answerable by searching the web with visible clues from the screenshot and the user's question, do that before asking the user for clarification.
            Only say what is missing when the screenshot and user message do not provide enough searchable clues to form a grounded query.
            """
        } else {
            prompt += """

            If the context is not enough to answer confidently, say what is missing in one sentence.
            """
        }

        if hasAttachments {
            prompt += """

            When referencing screenshot details, describe what you can directly observe. Use tools only if needed to resolve genuine ambiguity.
            """
        }

        return prompt
    }

    private func ensureActiveConversationID() -> UUID {
        if let activeConversationID = session.activeConversationID {
            return activeConversationID
        }

        let conversationID = UUID()
        session.activeConversationID = conversationID
        return conversationID
    }

    private func persistConversationSnapshot(conversationID: UUID, setError: @MainActor (String?) -> Void) {
        guard let conversationStore, !session.messages.isEmpty else {
            return
        }

        let existingConversation = session.savedConversations.first(where: { $0.id == conversationID })
        let updatedConversation = PersistedConversation(
            id: conversationID,
            title: conversationTitle(for: session.messages),
            createdAt: existingConversation?.createdAt ?? Date(),
            updatedAt: Date(),
            messages: session.messages
        )

        do {
            try conversationStore.saveConversation(updatedConversation)
            upsertSavedConversation(updatedConversation)
            publishSession()
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func upsertSavedConversation(_ conversation: PersistedConversation) {
        if let index = session.savedConversations.firstIndex(where: { $0.id == conversation.id }) {
            session.savedConversations[index] = conversation
        } else {
            session.savedConversations.append(conversation)
        }

        session.savedConversations.sort { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.updatedAt > rhs.updatedAt
        }

        session.selectedSavedConversationID = conversation.id
    }

    private func conversationTitle(for messages: [ConversationMessageDTO]) -> String {
        guard let firstUserText = messages.first(where: { $0.role == .user })?.text else {
            return "New Conversation"
        }

        let flattened = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else {
            return "New Conversation"
        }

        return String(flattened.prefix(60))
    }
}

enum ConversationContextMessages {
    nonisolated static func build(
        sessionMessages: [ConversationMessageDTO],
        selectedTextContexts: [AttachedTextContext] = [],
        browserPageContexts: [BrowserPageContext] = []
    ) -> [ConversationMessageDTO] {
        var messages: [ConversationMessageDTO] = []
        var seenBrowserURLs = Set<String>()
        var seenSelectedTextKeys = Set<String>()

        func appendBrowserPage(
            url: String,
            pageTitle: String,
            browserName: String,
            extractedText: String
        ) {
            guard seenBrowserURLs.insert(url).inserted else {
                return
            }

            var contextMessage = "Web page context from \(browserName) (\(url)):\nTitle: \(pageTitle)"
            if !extractedText.isEmpty {
                contextMessage += "\n\n\(extractedText)"
            }
            messages.append(ConversationMessageDTO(role: .system, text: contextMessage))
        }

        func appendSelectedText(text: String, appName: String?) {
            let key = "\(appName ?? "")\u{0}\(text)"
            guard seenSelectedTextKeys.insert(key).inserted else {
                return
            }

            let sourceDescription = appName ?? "the current app"
            let contextMessage = "Selected text from \(sourceDescription):\n\n\(text)"
            messages.append(ConversationMessageDTO(role: .system, text: contextMessage))
        }

        for message in sessionMessages where message.role == .user {
            for page in message.attachedBrowserPages {
                appendBrowserPage(
                    url: page.url,
                    pageTitle: page.pageTitle,
                    browserName: page.browserName,
                    extractedText: page.extractedText
                )
            }

            for selectedText in message.attachedSelectedTexts {
                appendSelectedText(text: selectedText.text, appName: selectedText.appName)
            }
        }

        for page in browserPageContexts.reversed() {
            appendBrowserPage(
                url: page.url,
                pageTitle: page.pageTitle,
                browserName: page.browserName,
                extractedText: page.extractedText
            )
        }

        for selectedTextContext in selectedTextContexts.reversed() {
            appendSelectedText(text: selectedTextContext.text, appName: selectedTextContext.appName)
        }

        return messages
    }
}