import Foundation

enum TTSSelectedTextLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            "English"
        case .french:
            "French"
        case .german:
            "German"
        }
    }

    var supertonicCode: String { rawValue }
}

struct TTSConfiguration: Codable, Equatable, Sendable {
    var baseURL: String
    var voice: String
    var language: String

    static let defaultValue = TTSConfiguration(
        baseURL: "http://127.0.0.1:7788",
        voice: "M1",
        language: TTSSelectedTextLanguage.english.supertonicCode
    )

    init(baseURL: String, voice: String, language: String) {
        self.baseURL = baseURL
        self.voice = voice
        self.language = language
    }

    init(selectedTextLanguage: TTSSelectedTextLanguage, baseURL: String = "http://127.0.0.1:7788", voice: String = "M1") {
        self.baseURL = baseURL
        self.voice = voice
        self.language = selectedTextLanguage.supertonicCode
    }

    var synthesisURL: URL? {
        URL(string: trimmedBaseURL + "/v1/tts")
    }

    private var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum TTSServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case emptyText
    case backendUnavailable
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "The TTS backend URL is invalid."
        case .emptyText:
            "There is no readable text to speak."
        case .backendUnavailable:
            "The TTS backend is not running. Start cue-tts-backend-experiment and try again."
        case .invalidResponse:
            "The TTS backend returned an invalid response."
        case .serverError(let message):
            message
        }
    }
}

enum TTSErrorResponseParser {
    static func message(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
