import Foundation

struct SearchSidecarLLMConfiguration: Encodable, Equatable, Sendable {
    let provider: String
    let baseURL: String
    let model: String
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL = "base_url"
        case model
        case apiKey = "api_key"
    }

    init(configuration: ConversationConfiguration) {
        switch configuration.provider {
        case .ollama:
            provider = "ollama"
            baseURL = configuration.ollamaBaseURL
            model = configuration.ollamaModel
            apiKey = configuration.ollamaAPIKey
        case .openAI:
            provider = "openai"
            baseURL = configuration.openAIBaseURL
            model = configuration.resolvedOpenAIModel
            apiKey = configuration.openAIAPIKey
        }
    }
}

struct SearchSidecarRequest: Encodable, Sendable {
    let query: String
    let corpusRoot: String
    let llm: SearchSidecarLLMConfiguration
    let maxSources: Int

    enum CodingKeys: String, CodingKey {
        case query
        case corpusRoot = "corpus_root"
        case llm
        case maxSources = "max_sources"
    }
}

struct SearchSidecarResponse: Decodable, Equatable, Sendable {
    let answer: String
    let sources: [SearchSidecarSource]
}

struct SearchSidecarSource: Decodable, Equatable, Sendable {
    let filePath: String
    let title: String
    let excerpt: String
    let section: String

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case title
        case excerpt
        case section
    }

    var resultSource: SearchResultSource {
        SearchResultSource(
            filePath: filePath,
            title: title,
            excerpt: excerpt,
            section: section
        )
    }
}

struct SearchSidecarHealthResponse: Decodable, Equatable, Sendable {
    let status: String
    let chunkCount: Int

    enum CodingKeys: String, CodingKey {
        case status
        case chunkCount = "chunk_count"
    }
}

struct SearchSidecarIndexRequest: Encodable, Equatable, Sendable {
    let corpusRoot: String

    enum CodingKeys: String, CodingKey {
        case corpusRoot = "corpus_root"
    }
}

struct SearchSidecarIndexResponse: Decodable, Equatable, Sendable {
    let filesScanned: Int
    let chunksIndexed: Int
    let corpusRoot: String

    enum CodingKeys: String, CodingKey {
        case filesScanned = "files_scanned"
        case chunksIndexed = "chunks_indexed"
        case corpusRoot = "corpus_root"
    }
}

enum SearchSidecarError: LocalizedError, Equatable {
    case invalidBaseURL
    case sidecarUnavailable(String)
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The cue-search sidecar URL is invalid."
        case let .sidecarUnavailable(message):
            message
        case .invalidResponse:
            "cue-search returned an unexpected response."
        case let .serverError(message):
            message
        }
    }
}

struct SearchSidecarClient: Sendable {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func health(baseURL: URL) async throws -> SearchSidecarHealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await urlSession.data(from: url)
        try validate(response: response, data: data)
        return try decode(SearchSidecarHealthResponse.self, from: data)
    }

    func search(baseURL: URL, request: SearchSidecarRequest) async throws -> SearchSidecarResponse {
        try await post(
            baseURL: baseURL,
            path: "v1/search",
            body: request,
            responseType: SearchSidecarResponse.self
        )
    }

    func syncIndex(baseURL: URL, corpusRoot: String) async throws -> SearchSidecarIndexResponse {
        try await post(
            baseURL: baseURL,
            path: "v1/index/sync",
            body: SearchSidecarIndexRequest(corpusRoot: corpusRoot),
            responseType: SearchSidecarIndexResponse.self
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        baseURL: URL,
        path: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validate(response: response, data: data)
        return try decode(responseType, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchSidecarError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let detail = serverErrorDetail(from: body) {
                throw SearchSidecarError.serverError(detail)
            }
            if httpResponse.statusCode == 404 || (500 ..< 600).contains(httpResponse.statusCode) {
                throw SearchSidecarError.sidecarUnavailable(
                    "cue-search is not reachable. Start it with `cue-search serve` and try again."
                )
            }
            throw SearchSidecarError.serverError(
                body.isEmpty ? "cue-search request failed with status \(httpResponse.statusCode)." : body
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SearchSidecarError.invalidResponse
        }
    }

    private func serverErrorDetail(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let detail = payload["detail"] as? String {
            return detail
        }

        return nil
    }
}
