import AVFoundation
import Foundation

@MainActor
final class TTSService {
    static let shared = TTSService()

    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private(set) var isGenerating = false

    private init() {}

    var isActive: Bool {
        isGenerating || player?.isPlaying == true
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        isGenerating = false
        stopPlayback()
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
    }

    func speak(
        text: String,
        configuration: TTSConfiguration = .defaultValue,
        onPlaybackStarted: (@MainActor () -> Void)? = nil
    ) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TTSServiceError.emptyText
        }

        guard let url = configuration.synthesisURL else {
            throw TTSServiceError.invalidConfiguration
        }

        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TTSSynthesisRequest(
                text: trimmedText,
                voice: configuration.voice,
                lang: configuration.language,
                steps: 8,
                responseFormat: "wav"
            )
        )

        isGenerating = true
        defer { isGenerating = false }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw TTSServiceError.backendUnavailable
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if let message = TTSErrorResponseParser.message(from: data) {
                throw TTSServiceError.serverError(message)
            }

            throw TTSServiceError.serverError("TTS synthesis failed with status \(httpResponse.statusCode).")
        }

        guard data.starts(with: Data("RIFF".utf8)) else {
            throw TTSServiceError.invalidResponse
        }

        try Task.checkCancellation()

        stopPlayback()

        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw TTSServiceError.invalidResponse
        }

        guard player?.play() == true else {
            player = nil
            throw TTSServiceError.invalidResponse
        }

        onPlaybackStarted?()
    }

    func speakInBackground(
        text: String,
        configuration: TTSConfiguration = .defaultValue,
        onPlaybackStarted: @escaping @MainActor () -> Void = {},
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (_ message: String) -> Void
    ) {
        speakTask?.cancel()
        speakTask = Task { @MainActor in
            defer { speakTask = nil }

            do {
                try await speak(
                    text: text,
                    configuration: configuration,
                    onPlaybackStarted: onPlaybackStarted
                )
                guard !Task.isCancelled else { return }
                onSuccess()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if let ttsError = error as? TTSServiceError {
                    onFailure(ttsError.errorDescription ?? "TTS playback failed.")
                } else {
                    onFailure(error.localizedDescription)
                }
            }
        }
    }
}

private struct TTSSynthesisRequest: Encodable {
    let text: String
    let voice: String
    let lang: String
    let steps: Int
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case text
        case voice
        case lang
        case steps
        case responseFormat = "response_format"
    }
}
