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

}
