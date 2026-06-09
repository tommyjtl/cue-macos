//
//  CuePrototypeTests.swift
//  CuePrototypeTests
//
//  Created by Tommy Liu on 5/4/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Cue

struct CuePrototypeTests {

    @Test func messageAttachmentStorePersistsAndReloadsImages() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-attachment-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let conversationID = UUID()
        let messageID = UUID()
        let screenshotID = UUID()
        let screenshotURL = rootDirectory.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try pngData.write(to: screenshotURL)

        let screenshot = CapturedScreenshot(
            id: screenshotID,
            createdAt: Date(),
            fileURL: screenshotURL,
            pixelSize: CGSize(width: 10, height: 10)
        )

        let store = MessageAttachmentStore(rootDirectory: rootDirectory)
        let references = try store.saveImages(
            from: [screenshot],
            conversationID: conversationID,
            messageID: messageID
        )

        #expect(references.count == 1)
        #expect(references[0].relativePath.contains(conversationID.uuidString))
        #expect(references[0].relativePath.contains(messageID.uuidString))

        let message = ConversationMessageDTO(
            id: messageID,
            role: .user,
            text: "What is in this screenshot?",
            imageAttachments: references
        )
        let resolved = try store.resolveMessageAttachments(for: [message])

        #expect(resolved[messageID]?.count == 1)
        #expect(resolved[messageID]?.first?.data == pngData)
    }

    @Test @MainActor func conversationExportIncludesAttachmentMetadataWithoutImageBytes() throws {
        let conversationID = UUID()
        let messageID = UUID()
        let imagePath = "conversation-attachments/\(conversationID.uuidString)/\(messageID.uuidString)/image.png"

        let conversation = PersistedConversation(
            id: conversationID,
            title: "Export Test",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            messages: [
                ConversationMessageDTO(
                    id: messageID,
                    role: .user,
                    text: "Summarize this",
                    attachedBrowserPages: [
                        AttachedBrowserPageReference(
                            url: "https://example.com/thread",
                            pageTitle: "Example Thread",
                            browserName: "Safari"
                        )
                    ],
                    attachedSelectedTexts: [
                        AttachedSelectedTextReference(text: "Selected passage", appName: "Mail")
                    ],
                    imageAttachments: [
                        ConversationImageAttachmentReference(
                            id: UUID(),
                            mimeType: "image/png",
                            relativePath: imagePath
                        )
                    ]
                ),
                ConversationMessageDTO(role: .assistant, text: "Here is the summary.")
            ]
        )

        let data = try ConversationExport.encode(conversation)
        let document = try JSONDecoder().decode(ExportedConversationDocument.self, from: data)

        #expect(document.messages.count == 2)
        let userMessage = try #require(document.messages.first)
        #expect(userMessage.attachments.count == 3)

        let imageAttachment = try #require(userMessage.attachments.first { $0.kind == .image })
        #expect(imageAttachment.path?.hasSuffix(imagePath) == true)

        #expect(userMessage.attachments.contains(.webPage(url: "https://example.com/thread")))
        #expect(userMessage.attachments.contains(.selectedText("Selected passage")))
    }

    @Test func attachedBrowserPageReferenceDeserializesLegacyPayloadWithoutExtractedText() {
        let legacyJSON = """
        {"url":"https://example.com/thread","pageTitle":"Example Thread","browserName":"Safari"}
        """

        let page = AttachedBrowserPageReference.deserialized(from: legacyJSON)

        #expect(page?.url == "https://example.com/thread")
        #expect(page?.pageTitle == "Example Thread")
        #expect(page?.browserName == "Safari")
        #expect(page?.extractedText == "")
    }

    @Test func conversationContextMessagesRebuildFromSessionHistory() {
        let browserPage = AttachedBrowserPageReference(
            url: "https://mail.example.com/inbox",
            pageTitle: "Inbox",
            browserName: "Safari",
            extractedText: "26 emails visible"
        )
        let sessionMessages = [
            ConversationMessageDTO(
                role: .user,
                text: "How many emails are there?",
                attachedBrowserPages: [browserPage],
                attachedSelectedTexts: [AttachedSelectedTextReference(text: "hello", appName: "Mail")]
            ),
            ConversationMessageDTO(role: .assistant, text: "26 total emails.")
        ]

        let contextualMessages = ConversationContextMessages.build(
            sessionMessages: sessionMessages,
            selectedTextContexts: [],
            browserPageContexts: []
        )

        #expect(contextualMessages.count == 2)
        #expect(contextualMessages.allSatisfy { $0.role == .system })
        #expect(contextualMessages[0].text.contains("26 emails visible"))
        #expect(contextualMessages[1].text.contains("hello"))
    }

    @Test func requestMessagesInterleaveContextBeforeEachUserTurn() {
        let firstUser = ConversationMessageDTO(
            role: .user,
            text: "fix my grammar",
            attachedSelectedTexts: [
                AttachedSelectedTextReference(text: "Hi Shan", appName: "Vivaldi")
            ],
            imageAttachments: [
                ConversationImageAttachmentReference(
                    id: UUID(),
                    mimeType: "image/png",
                    relativePath: "conv/msg/shot.png"
                )
            ]
        )
        let assistant = ConversationMessageDTO(role: .assistant, text: "Try: I am responding.")
        let pendingUser = ConversationMessageDTO(role: .user, text: "what was in my first attachment?")

        let requestMessages = ConversationContextMessages.buildRequestMessages(
            sessionMessages: [firstUser, assistant],
            pendingUserMessage: pendingUser
        )

        #expect(requestMessages.count == 5)
        #expect(requestMessages[0].role == .system)
        #expect(requestMessages[0].text.contains("Hi Shan"))
        #expect(requestMessages[1].role == .system)
        #expect(requestMessages[1].text.contains("screenshot"))
        #expect(requestMessages[1].text.contains("Image data is included"))
        #expect(requestMessages[2].id == firstUser.id)
        #expect(requestMessages[3].id == assistant.id)
        #expect(requestMessages[4].id == pendingUser.id)
    }

    @Test func requestMessagesUseOCRScreenshotNoticeWhenConfigured() {
        let userMessage = ConversationMessageDTO(
            role: .user,
            text: "read this",
            imageAttachments: [
                ConversationImageAttachmentReference(
                    id: UUID(),
                    mimeType: "image/png",
                    relativePath: "conv/msg/shot.png"
                )
            ]
        )

        let requestMessages = ConversationContextMessages.buildRequestMessages(
            sessionMessages: [],
            pendingUserMessage: userMessage,
            screenshotDeliveryMode: .ocrExtractedText
        )

        #expect(requestMessages.count == 2)
        #expect(requestMessages[0].text.contains("Text from the screenshot was extracted"))
        #expect(!requestMessages[0].text.contains("Image data is included"))
    }

    @Test func imageOCRFormattingUsesLightweightReference() {
        let single = ImageOCRFormatting.attachmentSection(imageCount: 1, extractedBlocks: ["Hello world"])
        #expect(single.hasPrefix("[Image attached — text extracted below]"))
        #expect(single.contains("Hello world"))

        let multiple = ImageOCRFormatting.attachmentSection(imageCount: 2, extractedBlocks: ["First", "Second"])
        #expect(multiple.contains("[2 images attached — text extracted below]"))
        #expect(multiple.contains("--- Image 1 ---"))
        #expect(multiple.contains("--- Image 2 ---"))
    }

    @Test func conversationRequestOCRPreprocessorReplacesImagePayloadWithText() {
        let messageID = UUID()
        let userMessage = ConversationMessageDTO(
            id: messageID,
            role: .user,
            text: "what does this say?",
            imageAttachments: [
                ConversationImageAttachmentReference(
                    id: UUID(),
                    mimeType: "image/png",
                    relativePath: "conv/msg/shot.png"
                )
            ]
        )
        let attachment = ConversationImageAttachmentDTO(mimeType: "image/png", data: Data([0x01]))

        let request = ConversationRequestOCRPreprocessor.apply(
            systemPrompt: "system",
            messages: [userMessage],
            messageAttachments: [messageID: [attachment]],
            ocrTextsByMessageID: [messageID: ["Line one\nLine two"]]
        )

        #expect(request.attachments(for: messageID).isEmpty)
        #expect(request.messages[0].text.contains("what does this say?"))
        #expect(request.messages[0].text.contains("[Image attached — text extracted below]"))
        #expect(request.messages[0].text.contains("Line one"))
    }

    @Test func conversationContextMessagesDedupesOverlayAndHistoricalContext() {
        let browserPage = BrowserPageContext(
            id: UUID(),
            createdAt: Date(),
            url: "https://example.com",
            pageTitle: "Example",
            extractedText: "Page body",
            browserName: "Safari"
        )
        let sessionMessages = [
            ConversationMessageDTO(
                role: .user,
                text: "First question",
                attachedBrowserPages: [browserPage.attachedReference]
            )
        ]

        let contextualMessages = ConversationContextMessages.build(
            sessionMessages: sessionMessages,
            selectedTextContexts: [],
            browserPageContexts: [browserPage]
        )

        #expect(contextualMessages.count == 1)
        #expect(contextualMessages[0].text.contains("Page body"))
    }

}

private struct ExportedConversationDocument: Decodable {
    struct Message: Decodable {
        let attachments: [ExportedConversationAttachment]
    }

    let messages: [Message]
}

private struct ExportedConversationAttachment: Decodable, Equatable {
    enum Kind: String, Decodable {
        case image
        case webPage
        case selectedText
    }

    let kind: Kind
    let path: String?
    let url: String?
    let text: String?

    static func image(path: String) -> Self {
        Self(kind: .image, path: path, url: nil, text: nil)
    }

    static func webPage(url: String) -> Self {
        Self(kind: .webPage, path: nil, url: url, text: nil)
    }

    static func selectedText(_ text: String) -> Self {
        Self(kind: .selectedText, path: nil, url: nil, text: text)
    }
}
