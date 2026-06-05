import Foundation
import Testing

@testable import Cue

struct TTSErrorResponseParserTests {
    @Test
    func parsesOpenAIStyleErrorEnvelope() {
        let data = Data(
            """
            {"error":{"message":"server not ready","type":"server_error","code":"not_ready"}}
            """.utf8
        )

        #expect(TTSErrorResponseParser.message(from: data) == "server not ready")
    }

    @Test
    func returnsNilForNonJSONPayload() {
        #expect(TTSErrorResponseParser.message(from: Data("not json".utf8)) == nil)
    }
}

struct TTSConfigurationTests {
    @Test
    func buildsSynthesisURLFromBaseURL() {
        let configuration = TTSConfiguration(selectedTextLanguage: .english)

        #expect(configuration.synthesisURL?.absoluteString == "http://127.0.0.1:7788/v1/tts")
        #expect(configuration.language == "en")
    }

    @Test
    func trimsTrailingSlashFromBaseURL() {
        let configuration = TTSConfiguration(
            baseURL: "http://127.0.0.1:7788/",
            voice: "M1",
            language: TTSSelectedTextLanguage.french.supertonicCode
        )

        #expect(configuration.synthesisURL?.absoluteString == "http://127.0.0.1:7788/v1/tts")
        #expect(configuration.language == "fr")
    }

    @Test
    func selectedTextLanguageDefaultsToEnglishWhenPreferenceMissing() {
        let defaults = UserDefaults.standard
        let key = AppPreferenceKeys.selectedTextTTSLanguageKey
        let previous = defaults.string(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        #expect(AppPreferenceKeys.selectedTextTTSLanguage == .english)
    }
}
