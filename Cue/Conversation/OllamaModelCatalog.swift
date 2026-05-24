import Foundation

enum OllamaThinkingSupport: Hashable {
    case unsupported
    case toggle
    case levels([OllamaThinkingMode])

    var allowedModes: [OllamaThinkingMode] {
        switch self {
        case .unsupported:
            [.off]
        case .toggle:
            [.off, .on]
        case let .levels(modes):
            modes
        }
    }

    var statusDescription: String {
        switch self {
        case .unsupported:
            "No curated thinking support metadata yet."
        case .toggle:
            "Supports on or off thinking mode."
        case .levels:
            "Supports thinking levels instead of a simple on or off toggle."
        }
    }

    func normalized(_ mode: OllamaThinkingMode) -> OllamaThinkingMode {
        switch self {
        case .unsupported:
            return .off
        case .toggle:
            return mode == .on ? .on : .off
        case let .levels(modes):
            if modes.contains(mode) {
                return mode
            }

            return modes.first ?? .off
        }
    }
}

enum OllamaThinkRequestValue: Encodable, Equatable {
    case boolean(Bool)
    case level(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .boolean(value):
            try container.encode(value)
        case let .level(value):
            try container.encode(value)
        }
    }
}

struct OllamaModelDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let recommendedTag: String
    let summary: String
    let matchPrefixes: [String]
    let thinkingSupport: OllamaThinkingSupport
}

struct OllamaModelOption: Identifiable, Hashable {
    enum Source: Hashable {
        case installed
        case curated
        case current
    }

    let modelName: String
    let title: String
    let summary: String
    let thinkingSupport: OllamaThinkingSupport
    let source: Source

    var id: String { modelName }

    var pickerTitle: String {
        switch source {
        case .installed, .current:
            return modelName
        case .curated:
            return "\(title) (\(modelName))"
        }
    }
}

enum OllamaModelCatalog {
    static let curatedDescriptors: [OllamaModelDescriptor] = [
        OllamaModelDescriptor(
            id: "gemma4",
            title: "Gemma 4",
            recommendedTag: "gemma4:latest",
            summary: "General-purpose local model family with vision, tools, and thinking support badges on Ollama.",
            matchPrefixes: ["gemma4"],
            thinkingSupport: .toggle
        ),
        OllamaModelDescriptor(
            id: "qwen3",
            title: "Qwen 3",
            recommendedTag: "qwen3:latest",
            summary: "Reasoning-oriented family explicitly listed in Ollama's thinking capability docs.",
            matchPrefixes: ["qwen3", "qwen3.5", "qwen3.6"],
            thinkingSupport: .toggle
        ),
        OllamaModelDescriptor(
            id: "deepseek-r1",
            title: "DeepSeek R1",
            recommendedTag: "deepseek-r1:latest",
            summary: "Reasoning-first model family explicitly listed in Ollama's thinking capability docs.",
            matchPrefixes: ["deepseek-r1"],
            thinkingSupport: .toggle
        ),
        OllamaModelDescriptor(
            id: "deepseek-v3.1",
            title: "DeepSeek v3.1",
            recommendedTag: "deepseek-v3.1:latest",
            summary: "Reasoning-capable DeepSeek family explicitly listed in Ollama's thinking capability docs.",
            matchPrefixes: ["deepseek-v3.1"],
            thinkingSupport: .toggle
        ),
        OllamaModelDescriptor(
            id: "gpt-oss",
            title: "GPT-OSS",
            recommendedTag: "gpt-oss:latest",
            summary: "Uses thinking levels rather than a boolean think flag.",
            matchPrefixes: ["gpt-oss"],
            thinkingSupport: .levels([.low, .medium, .high])
        )
    ]

    static var fallbackOptions: [OllamaModelOption] {
        curatedDescriptors.map { descriptor in
            OllamaModelOption(
                modelName: descriptor.recommendedTag,
                title: descriptor.title,
                summary: descriptor.summary,
                thinkingSupport: descriptor.thinkingSupport,
                source: .curated
            )
        }
    }

    static func descriptor(for modelName: String) -> OllamaModelDescriptor {
        let normalizedModelName = normalizedFamilyName(for: modelName)

        if let descriptor = curatedDescriptors.first(where: { descriptor in
            descriptor.matchPrefixes.contains { normalizedModelName.hasPrefix($0) }
        }) {
            return descriptor
        }

        return OllamaModelDescriptor(
            id: normalizedModelName.isEmpty ? modelName.lowercased() : normalizedModelName,
            title: modelName,
            recommendedTag: modelName,
            summary: "Installed model with no curated capability metadata yet.",
            matchPrefixes: [normalizedModelName],
            thinkingSupport: .unsupported
        )
    }

    static func option(for modelName: String, source: OllamaModelOption.Source) -> OllamaModelOption {
        let descriptor = descriptor(for: modelName)
        return OllamaModelOption(
            modelName: modelName,
            title: descriptor.title,
            summary: descriptor.summary,
            thinkingSupport: descriptor.thinkingSupport,
            source: source
        )
    }

    static func mergedOptions(_ options: [OllamaModelOption], currentModelName: String) -> [OllamaModelOption] {
        var merged = options

        if !currentModelName.isEmpty, !merged.contains(where: { $0.modelName == currentModelName }) {
            merged.insert(option(for: currentModelName, source: .current), at: 0)
        }

        return merged
    }

    private static func normalizedFamilyName(for modelName: String) -> String {
        let lowercased = modelName.lowercased()
        let withoutTag = lowercased.split(separator: ":", maxSplits: 1).first.map(String.init) ?? lowercased
        return withoutTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OllamaModelDiscoveryService {
    func fetchAvailableModels(baseURL: String) async throws -> [OllamaModelOption] {
        guard let url = URL(string: baseURL + "/api/tags") else {
            throw ConversationServiceError.invalidConfiguration("The Ollama base URL is invalid.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConversationServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ConversationServiceError.serverError("Could not load Ollama models from \(baseURL).")
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)

        return decoded.models
            .map { model in
                OllamaModelCatalog.option(for: model.name, source: .installed)
            }
            .sorted { $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending }
    }
}

extension ConversationConfiguration {
    var selectedOllamaModelDescriptor: OllamaModelDescriptor {
        OllamaModelCatalog.descriptor(for: ollamaModel)
    }

    var normalizedOllamaThinkingMode: OllamaThinkingMode {
        selectedOllamaModelDescriptor.thinkingSupport.normalized(ollamaThinkingMode)
    }

    var ollamaThinkRequestValue: OllamaThinkRequestValue? {
        switch selectedOllamaModelDescriptor.thinkingSupport {
        case .unsupported:
            return nil
        case .toggle:
            return .boolean(normalizedOllamaThinkingMode == .on)
        case .levels:
            switch normalizedOllamaThinkingMode {
            case .low, .medium, .high:
                return .level(normalizedOllamaThinkingMode.rawValue)
            case .off, .on:
                return nil
            }
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaTagsModel]
}

private struct OllamaTagsModel: Decodable {
    let name: String
}