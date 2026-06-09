import CoreGraphics
import Foundation
import ImageIO
import Vision

enum ImageOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Cue could not decode the image for text recognition."
        }
    }
}

enum ImageOCRFormatting {
    static func attachmentSection(imageCount: Int, extractedBlocks: [String]) -> String {
        let header = imageCount == 1
            ? "[Image attached — text extracted below]"
            : "[\(imageCount) images attached — text extracted below]"

        guard imageCount > 1 else {
            return "\(header)\n\n\(normalizedBlock(extractedBlocks.first ?? ""))"
        }

        var sections = [header]
        for (index, block) in extractedBlocks.enumerated() {
            sections.append("--- Image \(index + 1) ---\n\(normalizedBlock(block))")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func normalizedBlock(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No text recognized in image.)" : trimmed
    }
}

enum ImageOCRService {
    nonisolated static func extractTextBlocks(from attachments: [ConversationImageAttachmentDTO]) async throws -> [String] {
        var blocks: [String] = []
        blocks.reserveCapacity(attachments.count)

        for attachment in attachments {
            blocks.append(try await extractStructuredText(from: attachment.data))
        }

        return blocks
    }

    nonisolated static func extractStructuredText(from imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try performStructuredTextRecognition(on: imageData)
        }.value
    }

    nonisolated private static func performStructuredTextRecognition(on imageData: Data) throws -> String {
        guard let cgImage = cgImage(from: imageData) else {
            throw ImageOCRError.invalidImage
        }

        var recognitionError: Error?
        var extractedText = ""

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            extractedText = formatObservations(observations)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        if let recognitionError {
            throw recognitionError
        }

        return extractedText
    }

    nonisolated private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    nonisolated private static func formatObservations(_ observations: [VNRecognizedTextObservation]) -> String {
        struct LineItem {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
        }

        var items: [LineItem] = []
        items.reserveCapacity(observations.count)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }

            let box = observation.boundingBox
            items.append(
                LineItem(
                    text: candidate.string,
                    midY: box.midY,
                    minX: box.minX
                )
            )
        }

        guard !items.isEmpty else {
            return ""
        }

        let sorted = items.sorted {
            if abs($0.midY - $1.midY) > 0.02 {
                return $0.midY > $1.midY
            }
            return $0.minX < $1.minX
        }

        var lines: [[LineItem]] = []
        let lineThreshold: CGFloat = 0.02

        for item in sorted {
            if var lastLine = lines.last,
               let anchor = lastLine.first,
               abs(item.midY - anchor.midY) <= lineThreshold {
                lastLine.append(item)
                lines[lines.count - 1] = lastLine
            } else {
                lines.append([item])
            }
        }

        return lines
            .map { line in
                line
                    .sorted { $0.minX < $1.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }
}

enum ConversationRequestOCRPreprocessor {
    static func buildRequest(
        systemPrompt: String,
        messages: [ConversationMessageDTO],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        usesImageOCR: Bool,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> ConversationRequestDTO {
        guard usesImageOCR, !messageAttachments.isEmpty else {
            return ConversationRequestDTO(
                systemPrompt: systemPrompt,
                messages: messages,
                messageAttachments: messageAttachments
            )
        }

        onStatus?("Extracting text from images...")
        let ocrTextsByMessageID = try await extractOCRTexts(from: messageAttachments)
        return apply(
            systemPrompt: systemPrompt,
            messages: messages,
            messageAttachments: messageAttachments,
            ocrTextsByMessageID: ocrTextsByMessageID
        )
    }

    static func apply(
        systemPrompt: String,
        messages: [ConversationMessageDTO],
        messageAttachments: [UUID: [ConversationImageAttachmentDTO]],
        ocrTextsByMessageID: [UUID: [String]]
    ) -> ConversationRequestDTO {
        let transformedMessages = messages.map { message -> ConversationMessageDTO in
            guard message.role == .user,
                  let extractedBlocks = ocrTextsByMessageID[message.id],
                  !extractedBlocks.isEmpty else {
                return message
            }

            let ocrSection = ImageOCRFormatting.attachmentSection(
                imageCount: extractedBlocks.count,
                extractedBlocks: extractedBlocks
            )
            let mergedText = message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ocrSection
                : "\(message.text)\n\n\(ocrSection)"

            return ConversationMessageDTO(
                id: message.id,
                role: message.role,
                text: mergedText,
                attachedContextLabels: message.attachedContextLabels,
                attachedBrowserPages: message.attachedBrowserPages,
                attachedSelectedTexts: message.attachedSelectedTexts,
                imageAttachments: message.imageAttachments
            )
        }

        var clearedAttachments = messageAttachments
        for messageID in ocrTextsByMessageID.keys {
            clearedAttachments[messageID] = []
        }

        return ConversationRequestDTO(
            systemPrompt: systemPrompt,
            messages: transformedMessages,
            messageAttachments: clearedAttachments
        )
    }

    nonisolated static func extractOCRTexts(
        from messageAttachments: [UUID: [ConversationImageAttachmentDTO]]
    ) async throws -> [UUID: [String]] {
        var ocrTextsByMessageID: [UUID: [String]] = [:]

        for (messageID, attachments) in messageAttachments where !attachments.isEmpty {
            ocrTextsByMessageID[messageID] = try await ImageOCRService.extractTextBlocks(from: attachments)
        }

        return ocrTextsByMessageID
    }
}
