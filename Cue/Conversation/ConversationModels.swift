import Foundation

enum ConversationProvider: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama:
            "Ollama"
        case .openAI:
            "OpenAI"
        }
    }

    var supportsWebSearch: Bool {
        switch self {
        case .ollama, .openAI:
            true
        }
    }
}

enum OllamaThinkingMode: String, Codable, CaseIterable, Identifiable {
    case off
    case on
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .on:
            "On"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }
}

struct ConversationConfiguration: Codable, Equatable {
    var provider: ConversationProvider
    var ollamaBaseURL: String
    var ollamaModel: String
    var ollamaThinkingMode: OllamaThinkingMode
    var ollamaUseWebSearch: Bool
    var ollamaAPIKey: String
    var openAIBaseURL: String
    var openAIModel: String
    var openAIUseWebSearch: Bool
    var openAIAPIKey: String

    static let defaultValue = ConversationConfiguration(
        provider: .ollama,
        ollamaBaseURL: "http://localhost:11434",
        ollamaModel: "gemma4:latest",
        ollamaThinkingMode: .off,
        ollamaUseWebSearch: false,
        ollamaAPIKey: "",
        openAIBaseURL: "https://api.openai.com/v1",
        openAIModel: "gpt-5.4",
        openAIUseWebSearch: false,
        openAIAPIKey: ""
    )

    init(
        provider: ConversationProvider,
        ollamaBaseURL: String,
        ollamaModel: String,
        ollamaThinkingMode: OllamaThinkingMode = .off,
        ollamaUseWebSearch: Bool = false,
        ollamaAPIKey: String = "",
        openAIBaseURL: String,
        openAIModel: String,
        openAIUseWebSearch: Bool = false,
        openAIAPIKey: String
    ) {
        self.provider = provider
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.ollamaThinkingMode = ollamaThinkingMode
        self.ollamaUseWebSearch = ollamaUseWebSearch
        self.ollamaAPIKey = ollamaAPIKey
        self.openAIBaseURL = openAIBaseURL
        self.openAIModel = openAIModel
        self.openAIUseWebSearch = openAIUseWebSearch
        self.openAIAPIKey = openAIAPIKey
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case ollamaBaseURL
        case ollamaModel
        case ollamaThinkingMode
        case ollamaUseWebSearch
        case ollamaAPIKey
        case openAIBaseURL
        case openAIModel
        case openAIUseWebSearch
        case openAIAPIKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        provider = try container.decode(ConversationProvider.self, forKey: .provider)
        ollamaBaseURL = try container.decode(String.self, forKey: .ollamaBaseURL)
        ollamaModel = try container.decode(String.self, forKey: .ollamaModel)
        ollamaThinkingMode = try container.decodeIfPresent(OllamaThinkingMode.self, forKey: .ollamaThinkingMode) ?? .off
        ollamaUseWebSearch = try container.decodeIfPresent(Bool.self, forKey: .ollamaUseWebSearch) ?? false
        ollamaAPIKey = try container.decodeIfPresent(String.self, forKey: .ollamaAPIKey) ?? ""
        openAIBaseURL = try container.decode(String.self, forKey: .openAIBaseURL)
        openAIModel = try container.decode(String.self, forKey: .openAIModel)
        openAIUseWebSearch = try container.decodeIfPresent(Bool.self, forKey: .openAIUseWebSearch) ?? false
        openAIAPIKey = try container.decode(String.self, forKey: .openAIAPIKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(ollamaThinkingMode, forKey: .ollamaThinkingMode)
        try container.encode(ollamaUseWebSearch, forKey: .ollamaUseWebSearch)
        try container.encode(ollamaAPIKey, forKey: .ollamaAPIKey)
        try container.encode(openAIBaseURL, forKey: .openAIBaseURL)
        try container.encode(openAIModel, forKey: .openAIModel)
        try container.encode(openAIUseWebSearch, forKey: .openAIUseWebSearch)
        try container.encode(openAIAPIKey, forKey: .openAIAPIKey)
    }

    var providerDisplayName: String {
        switch provider {
        case .ollama:
            ollamaModel
        case .openAI:
            resolvedOpenAIModel
        }
    }

    var resolvedOpenAIModel: String {
        let trimmed = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultValue.openAIModel : trimmed
    }

    var usesWebSearch: Bool {
        switch provider {
        case .ollama:
            ollamaUseWebSearch
        case .openAI:
            openAIUseWebSearch
        }
    }

    mutating func setWebSearchEnabled(_ isEnabled: Bool) {
        switch provider {
        case .ollama:
            ollamaUseWebSearch = isEnabled
        case .openAI:
            openAIUseWebSearch = isEnabled
        }
    }
}

struct ConversationProcessBlockDTO: Identifiable, Equatable {
    enum Kind: String, Codable {
        case thinking
        case webSearch = "web_search"
        case webFetch = "web_fetch"
    }

    let id: UUID
    let kind: Kind
    let text: String
    let isComplete: Bool

    nonisolated init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        isComplete: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.isComplete = isComplete
    }
}

struct ConversationMessageDTO: Identifiable, Equatable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let processBlocks: [ConversationProcessBlockDTO]
    let attachedContextLabels: [String]

    nonisolated init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        thinkingText: String? = nil,
        isThinkingComplete: Bool = true,
        processBlocks: [ConversationProcessBlockDTO] = [],
        attachedContextLabels: [String] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachedContextLabels = attachedContextLabels
        if processBlocks.isEmpty, let thinkingText = thinkingText?.nilIfBlank {
            self.processBlocks = [ConversationProcessBlockDTO(kind: .thinking, text: thinkingText, isComplete: isThinkingComplete)]
        } else {
            self.processBlocks = processBlocks.filter { $0.text.nilIfBlank != nil }
        }
    }

    var thinkingText: String? {
        let value = processBlocks
            .filter { $0.kind == .thinking }
            .map(\.text)
            .joined(separator: "\n\n")

        return value.nilIfBlank
    }

    var isThinkingComplete: Bool {
        !processBlocks.contains(where: { $0.kind == .thinking && !$0.isComplete })
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

struct ConversationImageAttachmentDTO {
    let id: UUID
    let mimeType: String
    let data: Data

    init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }
}

struct ConversationRequestDTO {
    let systemPrompt: String
    let messages: [ConversationMessageDTO]
    let attachments: [ConversationImageAttachmentDTO]
}

struct ConversationResponseDTO {
    let message: ConversationMessageDTO
}

extension ConversationRequestDTO {
    var domainMessages: [Message] {
        messages.map { Message(dto: $0) }
    }
}

extension ConversationResponseDTO {
    var domainMessage: Message {
        Message(dto: message)
    }
}

enum ConversationServiceError: LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse
    case emptyResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case .invalidResponse:
            return "The model service returned an invalid response."
        case .emptyResponse:
            return "The model service returned an empty response."
        case let .serverError(message):
            return message
        }
    }
}
