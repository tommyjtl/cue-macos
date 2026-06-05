import Testing

@testable import Cue

struct TTSStatusToastCopyTests {
    @Test
    func mapsBackendUnavailableMessageToFriendlyToast() {
        let presentation = TTSStatusToastCopy.errorPresentation(
            for: "The TTS backend is not running. Start cue-tts-backend-experiment and try again."
        )

        #expect(presentation.title == "TTS backend isn't running.")
        #expect(presentation.subtitle?.contains("try again") == true)
    }

    @Test
    func passesThroughUnknownErrors() {
        let presentation = TTSStatusToastCopy.errorPresentation(for: "Synthesis failed.")

        #expect(presentation.title == "Synthesis failed.")
        #expect(presentation.subtitle == nil)
    }
}
