import Foundation

protocol ConversationProviderClient {
    func send(request: ConversationRequestDTO, configuration: ConversationConfiguration) async throws -> ConversationResponseDTO
}

protocol StreamingConversationProviderClient: ConversationProviderClient {
    func stream(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> ConversationResponseDTO
}

enum ConversationStreamEvent {
    case thinkingDelta(String)
    case thinkingFinished
    case toolResult(ConversationProcessBlockDTO)
    case contentDelta(String)
}

private struct ConversationProviderResolver {
    let ollamaClient: any StreamingConversationProviderClient
    let openAIClient: any StreamingConversationProviderClient

    func client(for provider: ConversationProvider) -> any ConversationProviderClient {
        switch provider {
        case .ollama:
            return ollamaClient
        case .openAI:
            return openAIClient
        }
    }

    func streamingClient(for provider: ConversationProvider) -> any StreamingConversationProviderClient {
        switch provider {
        case .ollama:
            return ollamaClient
        case .openAI:
            return openAIClient
        }
    }
}

struct ConversationService {
    private let providerResolver: ConversationProviderResolver

    init(
        ollamaClient: StreamingConversationProviderClient = OllamaConversationClient(),
        openAIClient: StreamingConversationProviderClient = OpenAIConversationClient()
    ) {
        providerResolver = ConversationProviderResolver(
            ollamaClient: ollamaClient,
            openAIClient: openAIClient
        )
    }

    func send(request: ConversationRequestDTO, configuration: ConversationConfiguration) async throws -> ConversationResponseDTO {
        try await providerResolver.client(for: configuration.provider).send(request: request, configuration: configuration)
    }

    func streamResponse(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> ConversationResponseDTO {
        try await providerResolver.streamingClient(for: configuration.provider).stream(
            request: request,
            configuration: configuration,
            onEvent: onEvent
        )
    }
}

private struct OllamaConversationClient: StreamingConversationProviderClient {
    private let hostedWebToolExecutor = OllamaHostedWebToolExecutor()

    func send(request: ConversationRequestDTO, configuration: ConversationConfiguration) async throws -> ConversationResponseDTO {
        let tools = ollamaTools(for: configuration)
        var messages = buildMessages(from: request)
        var accumulatedProcessBlocks: [ConversationProcessBlockDTO] = []

        for _ in 0 ..< 4 {
            let turnResult = try await sendTurn(messages: messages, tools: tools, configuration: configuration)

            if let thinking = turnResult.assistantMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines), !thinking.isEmpty {
                accumulatedProcessBlocks.append(ConversationProcessBlockDTO(kind: .thinking, text: thinking))
            }

            if turnResult.toolCalls.isEmpty {
                let content = turnResult.assistantMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else {
                    throw ConversationServiceError.emptyResponse
                }

                return ConversationResponseDTO(
                    message: ConversationMessageDTO(
                        role: .assistant,
                        text: content,
                        processBlocks: accumulatedProcessBlocks
                    )
                )
            }

            messages.append(turnResult.assistantMessage)
            let toolExecutionResults = try await execute(toolCalls: turnResult.toolCalls, configuration: configuration)
            accumulatedProcessBlocks.append(contentsOf: toolExecutionResults.map(\.processBlock))
            messages.append(contentsOf: toolExecutionResults.map(\.toolMessage))
        }

        throw ConversationServiceError.serverError("The Ollama tool loop did not finish after several tool calls.")
    }

    func stream(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> ConversationResponseDTO {
        let tools = ollamaTools(for: configuration)
        var messages = buildMessages(from: request)
        var accumulatedProcessBlocks: [ConversationProcessBlockDTO] = []
        var accumulatedContent = ""

        for _ in 0 ..< 4 {
            let turnResult = try await streamTurn(messages: messages, tools: tools, configuration: configuration, onEvent: onEvent)

            if let thinking = turnResult.assistantMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines), !thinking.isEmpty {
                accumulatedProcessBlocks.append(ConversationProcessBlockDTO(kind: .thinking, text: thinking))
            }

            if let content = turnResult.assistantMessage.content, !content.isEmpty {
                accumulatedContent += content
            }

            if turnResult.toolCalls.isEmpty {
                let content = accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else {
                    throw ConversationServiceError.emptyResponse
                }

                return ConversationResponseDTO(
                    message: ConversationMessageDTO(
                        role: .assistant,
                        text: content,
                        processBlocks: accumulatedProcessBlocks
                    )
                )
            }

            messages.append(turnResult.assistantMessage)
            let toolExecutionResults = try await execute(toolCalls: turnResult.toolCalls, configuration: configuration)
            for toolExecutionResult in toolExecutionResults {
                accumulatedProcessBlocks.append(toolExecutionResult.processBlock)
                await onEvent(.toolResult(toolExecutionResult.processBlock))
            }
            messages.append(contentsOf: toolExecutionResults.map(\.toolMessage))
        }

        throw ConversationServiceError.serverError("The Ollama tool loop did not finish after several tool calls.")
    }

    private func buildMessages(from request: ConversationRequestDTO) -> [OllamaChatMessage] {
        var messages: [OllamaChatMessage] = []
        messages.append(
            OllamaChatMessage(
                role: "system",
                content: request.systemPrompt,
                thinking: nil,
                images: nil,
                toolName: nil,
                toolCalls: nil
            )
        )

        for index in request.messages.indices {
            let message = request.messages[index]
            let isLatestUserMessage = index == request.messages.indices.last && message.role == .user
            let encodedImages = isLatestUserMessage ? request.attachments.map { $0.data.base64EncodedString() } : []

            messages.append(
                OllamaChatMessage(
                    role: message.role.rawValue,
                    content: message.text,
                    thinking: nil,
                    images: encodedImages.isEmpty ? nil : encodedImages,
                    toolName: nil,
                    toolCalls: nil
                )
            )
        }

        return messages
    }

    private func ollamaTools(for configuration: ConversationConfiguration) -> [OllamaToolDefinition]? {
        guard configuration.ollamaUseWebSearch else {
            return nil
        }

        return [.webSearch, .webFetch]
    }

    private func sendTurn(
        messages: [OllamaChatMessage],
        tools: [OllamaToolDefinition]?,
        configuration: ConversationConfiguration
    ) async throws -> OllamaTurnResult {
        guard let url = URL(string: configuration.ollamaBaseURL + "/api/chat") else {
            throw ConversationServiceError.invalidConfiguration("The Ollama base URL is invalid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequest(
            model: configuration.ollamaModel,
            stream: false,
            think: configuration.ollamaThinkRequestValue,
            messages: messages,
            tools: tools
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return OllamaTurnResult(assistantMessage: decoded.message.asAssistantMessage(), toolCalls: decoded.message.toolCalls ?? [])
    }

    private func streamTurn(
        messages: [OllamaChatMessage],
        tools: [OllamaToolDefinition]?,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> OllamaTurnResult {
        guard let url = URL(string: configuration.ollamaBaseURL + "/api/chat") else {
            throw ConversationServiceError.invalidConfiguration("The Ollama base URL is invalid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequest(
            model: configuration.ollamaModel,
            stream: true,
            think: configuration.ollamaThinkRequestValue,
            messages: messages,
            tools: tools
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var responseBody = ""
            for try await line in bytes.lines {
                responseBody.append(line)
            }

            throw conversationServerError(statusCode: httpResponse.statusCode, responseBody: responseBody)
        }

        var accumulatedThinking = ""
        var accumulatedContent = ""
        var accumulatedToolCalls: [OllamaToolCall] = []
        var hasSeenThinking = false
        var didFinishThinking = false

        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            guard let data = trimmedLine.data(using: .utf8) else {
                continue
            }

            let chunk = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

            if let thinkingDelta = chunk.message.thinking, !thinkingDelta.isEmpty {
                accumulatedThinking += thinkingDelta
                hasSeenThinking = true
                didFinishThinking = false
                await onEvent(.thinkingDelta(thinkingDelta))
            }

            if let contentDelta = chunk.message.content, !contentDelta.isEmpty {
                if hasSeenThinking, !didFinishThinking {
                    didFinishThinking = true
                    await onEvent(.thinkingFinished)
                }

                accumulatedContent += contentDelta
                await onEvent(.contentDelta(contentDelta))
            }

            if let toolCalls = chunk.message.toolCalls, !toolCalls.isEmpty {
                accumulatedToolCalls = mergeToolCalls(existing: accumulatedToolCalls, incoming: toolCalls)

                if hasSeenThinking, !didFinishThinking {
                    didFinishThinking = true
                    await onEvent(.thinkingFinished)
                }
            }

            if chunk.done {
                break
            }
        }

        if hasSeenThinking, !didFinishThinking {
            await onEvent(.thinkingFinished)
        }

        return OllamaTurnResult(
            assistantMessage: OllamaChatMessage(
                role: "assistant",
                content: accumulatedContent.isEmpty ? nil : accumulatedContent,
                thinking: accumulatedThinking.isEmpty ? nil : accumulatedThinking,
                images: nil,
                toolName: nil,
                toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
            ),
            toolCalls: accumulatedToolCalls
        )
    }

    private func execute(
        toolCalls: [OllamaToolCall],
        configuration: ConversationConfiguration
    ) async throws -> [OllamaToolExecutionResult] {
        var toolExecutionResults: [OllamaToolExecutionResult] = []

        for toolCall in toolCalls {
            let result = try await hostedWebToolExecutor.execute(toolCall, configuration: configuration)
            guard let processBlockKind = processBlockKind(for: toolCall.function.name) else {
                continue
            }

            toolExecutionResults.append(
                OllamaToolExecutionResult(
                    toolMessage: OllamaChatMessage(
                        role: "tool",
                        content: result,
                        thinking: nil,
                        images: nil,
                        toolName: toolCall.function.name,
                        toolCalls: nil
                    ),
                    processBlock: ConversationProcessBlockDTO(kind: processBlockKind, text: result)
                )
            )
        }

        return toolExecutionResults
    }

    private func processBlockKind(for toolName: String) -> ConversationProcessBlockDTO.Kind? {
        switch toolName {
        case "web_search":
            return .webSearch
        case "web_fetch":
            return .webFetch
        default:
            return nil
        }
    }

    private func mergeToolCalls(existing: [OllamaToolCall], incoming: [OllamaToolCall]) -> [OllamaToolCall] {
        var merged = existing

        for toolCall in incoming {
            if let index = toolCall.function.index,
               let existingIndex = merged.firstIndex(where: { $0.function.index == index }) {
                merged[existingIndex] = toolCall
            } else {
                merged.append(toolCall)
            }
        }

        return merged
    }
}

private struct OpenAIConversationClient: StreamingConversationProviderClient {
    func send(request: ConversationRequestDTO, configuration: ConversationConfiguration) async throws -> ConversationResponseDTO {
        if configuration.openAIUseWebSearch {
            return try await sendResponsesRequest(request: request, configuration: configuration)
        }

        let urlRequest = try makeURLRequest(request: request, configuration: configuration, stream: false)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let firstChoice = decoded.choices.first else {
            throw ConversationServiceError.emptyResponse
        }

        let content = firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ConversationServiceError.emptyResponse
        }

        return ConversationResponseDTO(message: ConversationMessageDTO(role: .assistant, text: content))
    }

    func stream(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> ConversationResponseDTO {
        if configuration.openAIUseWebSearch {
            return try await streamResponsesRequest(request: request, configuration: configuration, onEvent: onEvent)
        }

        let urlRequest = try makeURLRequest(request: request, configuration: configuration, stream: true)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var responseBody = ""
            for try await line in bytes.lines {
                responseBody.append(line)
            }

            throw conversationServerError(statusCode: httpResponse.statusCode, responseBody: responseBody)
        }

        var accumulatedContent = ""

        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, trimmedLine.hasPrefix("data:") else {
                continue
            }

            let payload = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8) else {
                continue
            }

            let chunk = try JSONDecoder().decode(OpenAIChatStreamResponse.self, from: data)
            for choice in chunk.choices {
                guard let delta = choice.delta.content, !delta.isEmpty else {
                    continue
                }

                accumulatedContent += delta
                await onEvent(.contentDelta(delta))
            }
        }

        let content = accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ConversationServiceError.emptyResponse
        }

        return ConversationResponseDTO(message: ConversationMessageDTO(role: .assistant, text: content))
    }

    private func sendResponsesRequest(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration
    ) async throws -> ConversationResponseDTO {
        let urlRequest = try makeResponsesURLRequest(request: request, configuration: configuration, stream: false)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validate(response: response, data: data)

        let content = try extractOpenAIResponseText(from: data).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw ConversationServiceError.emptyResponse
        }

        return ConversationResponseDTO(message: ConversationMessageDTO(role: .assistant, text: content))
    }

    private func streamResponsesRequest(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        onEvent: @escaping (ConversationStreamEvent) async -> Void
    ) async throws -> ConversationResponseDTO {
        let urlRequest = try makeResponsesURLRequest(request: request, configuration: configuration, stream: true)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var responseBody = ""
            for try await line in bytes.lines {
                responseBody.append(line)
            }

            throw conversationServerError(statusCode: httpResponse.statusCode, responseBody: responseBody)
        }

        var accumulatedContent = ""
        var pendingEventType: String?
        var eventDataLines: [String] = []
        var hasReportedWebSearch = false

        func handlePendingEvent() async throws {
            guard let pendingEventType, !eventDataLines.isEmpty else {
                return
            }

            let payload = eventDataLines.joined(separator: "\n")
            guard let data = payload.data(using: .utf8) else {
                return
            }

            let event = try parseOpenAIResponsesStreamEvent(from: data, fallbackType: pendingEventType)
            let eventType = event.type

            switch eventType {
            case "response.output_text.delta", "response.refusal.delta":
                guard let delta = event.delta, !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    break
                }

                accumulatedContent += delta
                await onEvent(.contentDelta(delta))
            case "response.output_text.done", "response.refusal.done", "response.completed":
                guard accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let completedText = event.completedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !completedText.isEmpty else {
                    break
                }

                accumulatedContent = completedText
                await onEvent(.contentDelta(completedText))
            case "response.web_search_call.in_progress", "response.web_search_call.searching":
                guard !hasReportedWebSearch else {
                    break
                }

                hasReportedWebSearch = true
                await onEvent(.toolResult(ConversationProcessBlockDTO(kind: .webSearch, text: "Searching the web...")))
            case "response.failed", "response.incomplete", "error":
                throw ConversationServiceError.serverError(event.errorMessage ?? "The OpenAI response failed.")
            default:
                break
            }
        }

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                try await handlePendingEvent()
                pendingEventType = nil
                eventDataLines.removeAll(keepingCapacity: true)
                continue
            }

            if line.hasPrefix("event:") {
                try await handlePendingEvent()
                eventDataLines.removeAll(keepingCapacity: true)
                pendingEventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("data:") {
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    try await handlePendingEvent()
                    break
                }

                eventDataLines.append(payload)
            }
        }

        try await handlePendingEvent()

        let content = accumulatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ConversationServiceError.emptyResponse
        }

        return ConversationResponseDTO(message: ConversationMessageDTO(role: .assistant, text: content))
    }

    private func buildMessages(from request: ConversationRequestDTO) -> [OpenAIChatMessage] {
        var messages: [OpenAIChatMessage] = []
        messages.append(OpenAIChatMessage(role: "system", content: [.text(request.systemPrompt)]))

        for index in request.messages.indices {
            let message = request.messages[index]

            if index == request.messages.indices.last, message.role == .user {
                var content: [OpenAIChatContent] = [.text(message.text)]
                content.append(contentsOf: request.attachments.map { attachment in
                    .imageURL("data:\(attachment.mimeType);base64,\(attachment.data.base64EncodedString())")
                })
                messages.append(OpenAIChatMessage(role: message.role.rawValue, content: content))
            } else {
                messages.append(OpenAIChatMessage(role: message.role.rawValue, content: [.text(message.text)]))
            }
        }

        return messages
    }

    private func makeURLRequest(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        stream: Bool
    ) throws -> URLRequest {
        let apiKey = configuration.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ConversationServiceError.invalidConfiguration("Add an OpenAI API key in Settings before using GPT.")
        }

        guard let url = URL(string: configuration.openAIBaseURL + "/chat/completions") else {
            throw ConversationServiceError.invalidConfiguration("The OpenAI base URL is invalid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIChatRequest(
            model: configuration.resolvedOpenAIModel,
            messages: buildMessages(from: request),
            stream: stream
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    private func makeResponsesURLRequest(
        request: ConversationRequestDTO,
        configuration: ConversationConfiguration,
        stream: Bool
    ) throws -> URLRequest {
        let apiKey = configuration.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ConversationServiceError.invalidConfiguration("Add an OpenAI API key in Settings before using GPT.")
        }

        guard let url = URL(string: configuration.openAIBaseURL + "/responses") else {
            throw ConversationServiceError.invalidConfiguration("The OpenAI base URL is invalid.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIResponsesRequest(
            model: configuration.resolvedOpenAIModel,
            instructions: request.systemPrompt,
            input: buildResponsesInput(from: request),
            tools: [.init(type: "web_search")],
            toolChoice: "auto",
            stream: stream
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    private func buildResponsesInput(from request: ConversationRequestDTO) -> [OpenAIResponsesInputMessage] {
        var input: [OpenAIResponsesInputMessage] = []

        for index in request.messages.indices {
            let message = request.messages[index]
            let isLatestUserMessage = index == request.messages.indices.last && message.role == .user
            let textContent: OpenAIResponsesInputContent = message.role == .assistant
                ? .outputText(message.text)
                : .inputText(message.text)
            var content: [OpenAIResponsesInputContent] = [textContent]

            if isLatestUserMessage {
                content.append(contentsOf: request.attachments.map { attachment in
                    .inputImage("data:\(attachment.mimeType);base64,\(attachment.data.base64EncodedString())")
                })
            }

            let role: String = switch message.role {
            case .system:
                "developer"
            case .user:
                "user"
            case .assistant:
                "assistant"
            }

            input.append(OpenAIResponsesInputMessage(role: role, content: content))
        }

        return input
    }

    private func extractOpenAIResponseText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversationServiceError.serverError("OpenAI returned a response in an unexpected format.")
        }

        return extractOpenAIResponseText(from: json) ?? ""
    }

    private func extractOpenAIResponseText(from json: [String: Any]) -> String? {
        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        guard let outputItems = json["output"] as? [[String: Any]] else {
            return nil
        }

        let text = outputItems.compactMap { item -> String? in
            guard let itemType = item["type"] as? String, itemType == "message",
                  let contentParts = item["content"] as? [[String: Any]] else {
                return nil
            }

            let itemText = contentParts.compactMap { contentPart -> String? in
                guard let contentType = contentPart["type"] as? String else {
                    return nil
                }

                switch contentType {
                case "output_text":
                    return contentPart["text"] as? String
                case "refusal":
                    return contentPart["refusal"] as? String
                default:
                    return nil
                }
            }.joined()

            return itemText.isEmpty ? nil : itemText
        }.joined()

        return text.isEmpty ? nil : text
    }

    private func parseOpenAIResponsesStreamEvent(
        from data: Data,
        fallbackType: String
    ) throws -> OpenAIResponsesParsedEvent {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversationServiceError.serverError("OpenAI returned a streaming event in an unexpected format.")
        }

        let type = (json["type"] as? String) ?? fallbackType
        let response = json["response"] as? [String: Any]
        let responseError = (response?["error"] as? [String: Any])?["message"] as? String

        return OpenAIResponsesParsedEvent(
            type: type,
            delta: json["delta"] as? String,
            completedText: (json["text"] as? String)
                ?? (json["refusal"] as? String)
                ?? response.flatMap(extractOpenAIResponseText(from:)),
            errorMessage: (json["message"] as? String) ?? responseError
        )
    }

}

private func validate(response: URLResponse, data: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw ConversationServiceError.invalidResponse
    }

    guard (200 ..< 300).contains(httpResponse.statusCode) else {
        let message = (try? JSONDecoder().decode(RemoteErrorEnvelope.self, from: data).message)
            ?? String(data: data, encoding: .utf8)
            ?? "The model service request failed with status code \(httpResponse.statusCode)."
        throw ConversationServiceError.serverError(message)
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let stream: Bool
    let think: OllamaThinkRequestValue?
    let messages: [OllamaChatMessage]
    let tools: [OllamaToolDefinition]?
}

private struct OllamaChatMessage: Encodable {
    let role: String
    let content: String?
    let thinking: String?
    let images: [String]?
    let toolName: String?
    let toolCalls: [OllamaToolCall]?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case thinking
        case images
        case toolName = "tool_name"
        case toolCalls = "tool_calls"
    }
}

private struct OllamaChatResponse: Decodable {
    struct ResponseMessage: Decodable {
        let role: String
        let content: String?
        let thinking: String?
        let toolCalls: [OllamaToolCall]?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case thinking
            case toolCalls = "tool_calls"
        }

        func asAssistantMessage() -> OllamaChatMessage {
            OllamaChatMessage(
                role: role,
                content: content,
                thinking: thinking,
                images: nil,
                toolName: nil,
                toolCalls: toolCalls
            )
        }
    }

    let message: ResponseMessage
    let done: Bool
}

private struct OllamaTurnResult {
    let assistantMessage: OllamaChatMessage
    let toolCalls: [OllamaToolCall]
}

private struct OllamaToolExecutionResult {
    let toolMessage: OllamaChatMessage
    let processBlock: ConversationProcessBlockDTO
}

private struct OllamaToolDefinition: Encodable {
    struct FunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: JSONObjectValue
    }

    let type = "function"
    let function: FunctionDefinition

    static let webSearch = OllamaToolDefinition(
        function: FunctionDefinition(
            name: "web_search",
            description: "Search the web for up-to-date information and return the most relevant results.",
            parameters: .object([
                "type": .string("object"),
                "required": .array([.string("query")]),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("The search query to run on the web.")
                    ]),
                    "max_results": .object([
                        "type": .string("integer"),
                        "description": .string("The maximum number of search results to return."),
                        "minimum": .number(1),
                        "maximum": .number(10)
                    ])
                ])
            ])
        )
    )

    static let webFetch = OllamaToolDefinition(
        function: FunctionDefinition(
            name: "web_fetch",
            description: "Fetch the contents of a specific web page by URL.",
            parameters: .object([
                "type": .string("object"),
                "required": .array([.string("url")]),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("The URL of the web page to fetch.")
                    ])
                ])
            ])
        )
    )
}

private struct OllamaToolCall: Codable {
    struct FunctionCall: Codable {
        let index: Int?
        let name: String
        let arguments: [String: JSONObjectValue]
    }

    let function: FunctionCall
}

private enum JSONObjectValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONObjectValue])
    case array([JSONObjectValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let object = try? container.decode([String: JSONObjectValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONObjectValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }

        return nil
    }

    var intValue: Int? {
        if case let .number(value) = self {
            return Int(value)
        }

        return nil
    }
}

private struct OllamaHostedWebToolExecutor {
    private enum Endpoint {
        static let search = "https://ollama.com/api/web_search"
        static let fetch = "https://ollama.com/api/web_fetch"
    }

    func execute(
        _ toolCall: OllamaToolCall,
        configuration: ConversationConfiguration
    ) async throws -> String {
        switch toolCall.function.name {
        case "web_search":
            return try await executeWebSearch(arguments: toolCall.function.arguments, configuration: configuration)
        case "web_fetch":
            return try await executeWebFetch(arguments: toolCall.function.arguments, configuration: configuration)
        default:
            return "Tool \(toolCall.function.name) is not supported by Cue."
        }
    }

    private func executeWebSearch(
        arguments: [String: JSONObjectValue],
        configuration: ConversationConfiguration
    ) async throws -> String {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return "Web search failed because the query argument was missing."
        }

        guard let apiKey = apiKey(for: configuration) else {
            return "Web search is enabled, but Cue could not find an Ollama API key in Settings or an OLLAMA_API_KEY in the app environment."
        }

        guard let url = URL(string: Endpoint.search) else {
            throw ConversationServiceError.invalidConfiguration("The Ollama web search endpoint is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OllamaHostedWebSearchRequest(
                query: query,
                maxResults: arguments["max_results"]?.intValue
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OllamaHostedWebSearchResponse.self, from: data)
        guard !decoded.results.isEmpty else {
            return "Web search returned no results for: \(query)"
        }

        let body = decoded.results.enumerated().map { index, result in
            "\(index + 1). \(result.title)\nURL: \(result.url)\nSnippet: \(truncate(result.content, limit: 500))"
        }.joined(separator: "\n\n")

        return truncate("Search results for: \(query)\n\n\(body)", limit: 4_000)
    }

    private func executeWebFetch(
        arguments: [String: JSONObjectValue],
        configuration: ConversationConfiguration
    ) async throws -> String {
        guard let urlString = arguments["url"]?.stringValue, !urlString.isEmpty else {
            return "Web fetch failed because the url argument was missing."
        }

        guard let apiKey = apiKey(for: configuration) else {
            return "Web fetch is enabled, but Cue could not find an Ollama API key in Settings or an OLLAMA_API_KEY in the app environment."
        }

        guard let url = URL(string: Endpoint.fetch) else {
            throw ConversationServiceError.invalidConfiguration("The Ollama web fetch endpoint is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OllamaHostedWebFetchRequest(url: urlString))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(OllamaHostedWebFetchResponse.self, from: data)
        let links = decoded.links.prefix(8).joined(separator: "\n")
        let linksSection = links.isEmpty ? "" : "\n\nLinks:\n\(links)"

        return truncate(
            "Fetched page: \(decoded.title)\nURL: \(urlString)\n\nContent:\n\(decoded.content)\(linksSection)",
            limit: 4_000
        )
    }

    private func apiKey(for configuration: ConversationConfiguration) -> String? {
        let configuredValue = configuration.ollamaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredValue.isEmpty {
            return configuredValue
        }

        let environmentValue = ProcessInfo.processInfo.environment["OLLAMA_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let environmentValue, !environmentValue.isEmpty else {
            return nil
        }

        return environmentValue
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let cutoffIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<cutoffIndex]) + "..."
    }
}

private struct OllamaHostedWebSearchRequest: Encodable {
    let query: String
    let maxResults: Int?

    private enum CodingKeys: String, CodingKey {
        case query
        case maxResults = "max_results"
    }
}

private struct OllamaHostedWebSearchResponse: Decodable {
    struct Result: Decodable {
        let title: String
        let url: String
        let content: String
    }

    let results: [Result]
}

private struct OllamaHostedWebFetchRequest: Encodable {
    let url: String
}

private struct OllamaHostedWebFetchResponse: Decodable {
    let title: String
    let content: String
    let links: [String]
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
}

private struct OpenAIResponsesRequest: Encodable {
    struct Tool: Encodable {
        let type: String
    }

    let model: String
    let instructions: String
    let input: [OpenAIResponsesInputMessage]
    let tools: [Tool]
    let toolChoice: String
    let stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case toolChoice = "tool_choice"
        case stream
    }
}

private struct OpenAIResponsesInputMessage: Encodable {
    let role: String
    let content: [OpenAIResponsesInputContent]
}

private enum OpenAIResponsesInputContent: Encodable {
    case inputText(String)
    case outputText(String)
    case inputImage(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .inputText(text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .outputText(text):
            try container.encode("output_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .inputImage(imageURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct OpenAIChatMessage: Encodable {
    let role: String
    let content: [OpenAIChatContent]
}

private enum OpenAIChatContent: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURL: Encodable {
        let url: String
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct ChoiceMessage: Decodable {
            let role: String
            let content: String
        }

        let message: ChoiceMessage
    }

    let choices: [Choice]
}

private struct OpenAIChatStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private struct OpenAIResponsesParsedEvent {
    let type: String
    let delta: String?
    let completedText: String?
    let errorMessage: String?
}

private struct RemoteErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError?

    var message: String? {
        error?.message
    }
}

private func conversationServerError(statusCode: Int, responseBody: String) -> ConversationServiceError {
    if let data = responseBody.data(using: .utf8),
       let envelope = try? JSONDecoder().decode(RemoteErrorEnvelope.self, from: data),
       let message = envelope.message {
        return .serverError(message)
    }

    if !responseBody.isEmpty {
        return .serverError(responseBody)
    }

    return .serverError("The model service request failed with status code \(statusCode).")
}