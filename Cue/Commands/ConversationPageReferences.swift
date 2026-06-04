import Foundation

enum ConversationPageReferences {
    struct PageReference: Equatable {
        let title: String
        let url: String
        let browserName: String
    }

    static func oldestPageReference(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO]
    ) -> PageReference? {
        for message in conversationMessages where message.role == .user {
            if let page = message.attachedBrowserPages.last {
                return PageReference(
                    title: displayTitle(for: page.pageTitle, url: page.url),
                    url: page.url,
                    browserName: page.browserName
                )
            }
        }

        for message in contextualMessages where message.role == .system {
            guard let reference = referenceFromContextMessage(message) else {
                continue
            }

            return reference
        }

        // Context stack inserts at index 0, so the tail is the oldest page.
        if let page = browserPageContexts.last {
            return PageReference(
                title: displayTitle(for: page.pageTitle, url: page.url),
                url: page.url,
                browserName: page.browserName
            )
        }

        return nil
    }

    static func collectReferences(
        browserPageContexts: [BrowserPageContext],
        contextualMessages: [ConversationMessageDTO],
        conversationMessages: [ConversationMessageDTO]
    ) -> [PageReference] {
        var references: [PageReference] = []
        var seenURLs = Set<String>()

        func appendReference(title: String, url: String, browserName: String) {
            guard seenURLs.insert(url).inserted else {
                return
            }

            references.append(
                PageReference(
                    title: displayTitle(for: title, url: url),
                    url: url,
                    browserName: browserName
                )
            )
        }

        for page in browserPageContexts {
            appendReference(title: page.pageTitle, url: page.url, browserName: page.browserName)
        }

        for message in contextualMessages where message.role == .system {
            guard let reference = referenceFromContextMessage(message) else {
                continue
            }

            appendReference(title: reference.title, url: reference.url, browserName: reference.browserName)
        }

        for message in conversationMessages {
            for page in message.attachedBrowserPages {
                appendReference(title: page.pageTitle, url: page.url, browserName: page.browserName)
            }
        }

        return references
    }

    static func referenceContextMessage(for references: [PageReference]) -> ConversationMessageDTO? {
        guard !references.isEmpty else {
            return nil
        }

        let lines = references.map { reference in
            "- \(reference.title): \(reference.url) (\(reference.browserName))"
        }

        return ConversationMessageDTO(
            role: .system,
            text: """
            Attached web page references for this note:
            \(lines.joined(separator: "\n"))

            Cue will append these as markdown links in a ## References section.
            """
        )
    }

    static func primaryPageContextMessage(for reference: PageReference) -> ConversationMessageDTO {
        ConversationMessageDTO(
            role: .system,
            text: """
            PRIMARY page to bookmark (oldest page in this session):
            - \(reference.title): \(reference.url) (\(reference.browserName))

            Center the markdown note on this page. Include a prominent link to this URL in the body.
            Do not append a separate ## References section for other URLs.
            """
        )
    }

    private static func referenceFromContextMessage(_ message: ConversationMessageDTO) -> PageReference? {
        guard message.text.hasPrefix("Web page context from ") else {
            return nil
        }

        guard let urlStart = message.text.firstIndex(of: "("),
              let urlEnd = message.text[urlStart...].firstIndex(of: ")"),
              urlStart < urlEnd else {
            return nil
        }

        let url = String(message.text[message.text.index(after: urlStart)..<urlEnd])
        let browserName = message.text[
            message.text.index(message.text.startIndex, offsetBy: "Web page context from ".count)..<urlStart
        ]
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let pageTitle = message.text
            .components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("Title: ") })
            .map { String($0.dropFirst("Title: ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""

        return PageReference(
            title: displayTitle(for: pageTitle, url: url),
            url: url,
            browserName: browserName.isEmpty ? "Web" : browserName
        )
    }

    private static func displayTitle(for pageTitle: String, url: String) -> String {
        let trimmedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? url : trimmedTitle
    }
}
