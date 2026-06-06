import AVFoundation
import Foundation

@MainActor
final class TTSService {
    static let shared = TTSService()

    private var player: AVAudioPlayer?
    private var playbackDelegate: TTSPlaybackDelegate?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var speakTask: Task<Void, Never>?
    private(set) var isGenerating = false
    private(set) var isSpeaking = false

    private init() {}

    var isActive: Bool {
        isGenerating || isSpeaking
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
        playbackDelegate = nil
        isSpeaking = false
        resumePlaybackContinuation(with: .failure(CancellationError()))
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

        try await playUntilFinished(data: data, onPlaybackStarted: onPlaybackStarted)
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

    private func playUntilFinished(
        data: Data,
        onPlaybackStarted: (@MainActor () -> Void)?
    ) async throws {
        stopPlayback()

        let delegate = TTSPlaybackDelegate()
        playbackDelegate = delegate

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            playbackDelegate = nil
            throw TTSServiceError.invalidResponse
        }

        self.player = player
        player.delegate = delegate

        delegate.onFinish = { [weak self] successfully in
            Task { @MainActor in
                self?.handlePlaybackFinished(successfully: successfully)
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                playbackContinuation = continuation

                guard player.play() else {
                    playbackContinuation = nil
                    isSpeaking = false
                    continuation.resume(throwing: TTSServiceError.invalidResponse)
                    return
                }

                isSpeaking = true
                onPlaybackStarted?()
            }
        } onCancel: {
            Task { @MainActor in
                self.stopPlayback()
            }
        }
    }

    private func handlePlaybackFinished(successfully: Bool) {
        player = nil
        playbackDelegate = nil
        isSpeaking = false

        if successfully {
            resumePlaybackContinuation(with: .success(()))
        } else {
            resumePlaybackContinuation(with: .failure(TTSServiceError.invalidResponse))
        }
    }

    private func resumePlaybackContinuation(with result: Result<Void, Error>) {
        guard let continuation = playbackContinuation else { return }
        playbackContinuation = nil

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class TTSPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: ((Bool) -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?(flag)
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
