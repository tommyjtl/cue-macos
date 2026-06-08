import Foundation

enum MarkExportDefaultSynthesisInstruction {
    enum Scenario: String, Equatable {
        case youtubeVideo

        var displayLabel: String {
            switch self {
            case .youtubeVideo:
                "YouTube video"
            }
        }
    }

    struct PresetGeneratingContext: Equatable, Sendable {
        let scenarioLabel: String
        let hint: String
    }

    struct Result: Equatable {
        let scenario: Scenario
        let instruction: String

        var presetGeneratingContext: PresetGeneratingContext {
            PresetGeneratingContext(
                scenarioLabel: scenario.displayLabel,
                hint: instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func resolve(
        userHint: String,
        hasConversation: Bool,
        primaryPage: ConversationPageReferences.PageReference,
        contextualMessages: [ConversationMessageDTO]
    ) -> Result? {
        guard userHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard !hasConversation else {
            return nil
        }

        guard isYouTubeURL(primaryPage.url) else {
            return nil
        }

        return Result(
            scenario: .youtubeVideo,
            instruction: youtubeVideoInstruction(hasSelectedText: hasSelectedText(in: contextualMessages))
        )
    }

    static func isYouTubeURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }

        if host == "youtu.be" || host == "www.youtu.be" {
            return true
        }

        if host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" {
            return true
        }

        return host.hasSuffix(".youtube.com")
    }

    private static func youtubeVideoInstruction(hasSelectedText: Bool) -> String {
        if hasSelectedText {
            return """
Summarize this YouTube video in ## Highlights with at least 3 bullets or a short paragraph covering the main topics and key takeaways. 
Treat any attached selected notes or transcript text as primary source material—do not return only the video link.
            """
        }

        return """
Summarize this YouTube video in ## Highlights with at least 3 bullets or a short paragraph covering the main topics and 
key takeaways from all attached context—do not return only the video link.
        """
    }

    private static func hasSelectedText(in contextualMessages: [ConversationMessageDTO]) -> Bool {
        contextualMessages.contains { message in
            message.role == .system && message.text.hasPrefix("Selected text from")
        }
    }
}
