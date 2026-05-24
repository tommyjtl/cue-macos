import AppKit
import Observation
import SwiftUI
import Textual

@MainActor
@Observable
final class ContextPanelViewModel {
    enum Mode {
        case stack
        case chat
    }

    var screenshots: [CapturedScreenshot] = []
    var selectedTextContexts: [SelectedTextManager.SelectionSnapshot] = []
    var browserPageContexts: [BrowserPageContext] = []
    var messages: [ConversationMessageDTO] = []
    var mode: Mode = .stack
    var draftMessage = ""
    var isSending = false
    var canCancelSend = false
    var providerDisplayName = ""
    var composerFocusRequestID = UUID()
    var hasSavedConversations = false
    var supportsWebSearch = false
    var isWebSearchEnabled = false
}

struct ContextStackView: View {
    private enum ScrollAnchorID {
        static let transcriptBottom = "transcript-bottom"
    }

    private enum StackLayout {
        static let shadowBleed: CGFloat = 36
        static let stageSize: CGFloat = 208
        static let outerSize: CGFloat = stageSize + (shadowBleed * 2)
    }

    @Bindable var model: ContextPanelViewModel
    let onClear: () -> Void
    let onCloseChat: () -> Void
    let onSend: () -> Void
    let onCancelSend: () -> Void
    let onLoadMostRecent: () -> Void
    let onSetWebSearchEnabled: (Bool) -> Void
    let onRemoveContextItem: (ContextPreviewItem) -> Void
    let onEscape: () -> Void

    @State private var scrollDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.mode {
            case .stack:
                stackContent
            case .chat:
                chatContent
            }
        }
        .padding(model.mode == .chat ? 14 : 0)
        .frame(width: model.mode == .chat ? 360 : StackLayout.outerSize)
        .background(backgroundShape)
        .overlay(borderShape)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if model.mode == .chat {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        if model.mode == .chat {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
    }

    private var stackContent: some View {
        let previewItems = contextPreviewItems
        let visibleItems = Array(previewItems.prefix(2))
        let overflowCount = max(0, previewItems.count - visibleItems.count)

        return ZStack(alignment: .topTrailing) {
            ZStack {
                if visibleItems.count > 1 {
                    ContextStackPreviewCard(item: visibleItems[1])
                        .rotationEffect(.degrees(6))
                        .offset(x: 14, y: -6)
                        .scaleEffect(0.93)
                }

                if let primaryItem = visibleItems.first {
                    ContextStackPreviewCard(item: primaryItem)
                        .rotationEffect(.degrees(visibleItems.count > 1 ? -5 : -2))
                        .offset(x: visibleItems.count > 1 ? -8 : 0, y: visibleItems.count > 1 ? 8 : 2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 54)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    )
                    .padding(14)
            }
        }
        .frame(width: StackLayout.stageSize, height: StackLayout.stageSize)
        .padding(StackLayout.shadowBleed)
    }

    private var chatContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Cue")
                        .font(.headline)

                    Text(chatSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    onCloseChat()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close composer")
            }
            .background(WindowDragArea())

            Color.clear
                .frame(height: 18)
                .contentShape(Rectangle())
                .background(WindowDragArea())

            transcriptContent

            if !contextPreviewItems.isEmpty {
                ComposerContextShelf(items: contextPreviewItems, onRemove: onRemoveContextItem)
            }

            ComposerTextField(
                text: $model.draftMessage,
                placeholder: composerPlaceholder,
                focusRequestID: model.composerFocusRequestID,
                onSubmit: {
                    guard !model.isSending,
                          !model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return
                    }

                    onSend()
                },
                onEscape: onEscape
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(height: 40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(alignment: .center) {
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.borderless)

                if model.messages.isEmpty && model.hasSavedConversations {
                    Button("Load recent chat") {
                        onLoadMostRecent()
                    }
                    .buttonStyle(.borderless)
                }

                if model.supportsWebSearch {
                    Toggle("Web Search", isOn: webSearchBinding)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help(model.isWebSearchEnabled ? "Disable web search for this provider" : "Enable web search for this provider")

                    Text("Web Search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    if model.isSending {
                        onCancelSend()
                    } else {
                        onSend()
                    }
                } label: {
                    Image(systemName: model.isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.isSending ? .red : .primary)
                .accessibilityLabel(model.isSending ? "Stop response" : "Send message")
                .disabled(!model.isSending && model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.messages.isEmpty {
                Text(emptyConversationText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.messages) { message in
                                ConversationMessageBubble(
                                    message: message,
                                    assistantDisplayName: assistantDisplayName,
                                    rendersStreamingText: model.isSending && message.id == model.messages.last?.id
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(ScrollAnchorID.transcriptBottom)
                        }
                    }
                    .onAppear {
                        scrollTranscriptToBottom(using: proxy)
                    }
                    .onChange(of: model.messages) { _, _ in
                        scrollDebounceTask?.cancel()
                        scrollDebounceTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(100))
                            guard !Task.isCancelled else { return }
                            scrollTranscriptToBottom(using: proxy)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            if model.isSending {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Waiting for \(assistantDisplayName)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var webSearchBinding: Binding<Bool> {
        Binding(
            get: { model.isWebSearchEnabled },
            set: { isEnabled in
                model.isWebSearchEnabled = isEnabled
                onSetWebSearchEnabled(isEnabled)
            }
        )
    }

    private var assistantDisplayName: String {
        model.providerDisplayName.isEmpty ? "the selected model" : model.providerDisplayName
    }

    private var chatSubtitle: String {
        let contextItemCount = model.screenshots.count + model.selectedTextContexts.count + model.browserPageContexts.count
        let attachmentSummary = contextItemCount == 1 ? "1 context item attached" : "\(contextItemCount) context items attached"
        if model.providerDisplayName.isEmpty {
            return attachmentSummary
        }

        return "\(attachmentSummary) • \(model.providerDisplayName)"
    }

    private var emptyConversationText: String {
        "Ask a question about the attached context. Replies will come from \(assistantDisplayName)."
    }

    private var composerPlaceholder: String {
        if !model.browserPageContexts.isEmpty {
            return "Ask about the attached web page..."
        }
        return model.selectedTextContexts.isEmpty ? "Ask about these screenshots..." : "Ask about the attached context..."
    }

    private func scrollTranscriptToBottom(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(ScrollAnchorID.transcriptBottom, anchor: .bottom)
        }
    }

    private var contextPreviewItems: [ContextPreviewItem] {
        var items = model.screenshots.map { ContextPreviewItem.screenshot($0) }
        items.append(contentsOf: model.selectedTextContexts.map(ContextPreviewItem.selectedText))
        items.append(contentsOf: model.browserPageContexts.map(ContextPreviewItem.browserPage))
        return items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }
}

enum ContextPreviewItem: Identifiable {
    case screenshot(CapturedScreenshot)
    case selectedText(SelectedTextManager.SelectionSnapshot)
    case browserPage(BrowserPageContext)

    var id: String {
        switch self {
        case let .screenshot(screenshot):
            return "screenshot-\(screenshot.id.uuidString)"
        case let .selectedText(selectionSnapshot):
            return "selected-text-\(selectionSnapshot.createdAt.timeIntervalSince1970)"
        case let .browserPage(context):
            return "browser-page-\(context.id.uuidString)"
        }
    }

    var createdAt: Date {
        switch self {
        case let .screenshot(screenshot):
            return screenshot.createdAt
        case let .selectedText(selectionSnapshot):
            return selectionSnapshot.createdAt
        case let .browserPage(context):
            return context.createdAt
        }
    }
}

private struct ConversationMessageBubble: View {
    let message: ConversationMessageDTO
    let assistantDisplayName: String
    let rendersStreamingText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(senderLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(message.processBlocks) { block in
                processBlockView(for: block)
            }

            if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messageBody
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !message.attachedContextLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.attachedContextLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .padding(.top, 2)
            }

            if message.role == .assistant && !rendersStreamingText && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                    .padding(.top, 4)
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var senderLabel: String {
        switch message.role {
        case .user:
            "You"
        case .assistant:
            assistantDisplayName
        case .system:
            "System"
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        if message.role == .assistant {
            if rendersStreamingText {
                let parts = message.text.components(separatedBy: "\n\n")
                if parts.count > 1 {
                    let completedMarkdown = parts.dropLast().joined(separator: "\n\n")
                    let tail = parts.last ?? ""
                    VStack(alignment: .leading, spacing: 4) {
                        StructuredText(markdown: completedMarkdown)
                            .textual.structuredTextStyle(.default)
                            .textual.textSelection(.enabled)
                        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text(message.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                StructuredText(markdown: message.text)
                    .textual.structuredTextStyle(.default)
                    .textual.textSelection(.enabled)
            }
        } else {
            Text(message.text)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch message.role {
        case .user:
            AnyShapeStyle(.regularMaterial)
        case .assistant:
            AnyShapeStyle(.thinMaterial)
        case .system:
            AnyShapeStyle(.quinary)
        }
    }

    @ViewBuilder
    private func processBlockView(for block: ConversationProcessBlockDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(processBlockTitle(for: block))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(processBlockPreviewText(for: block))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quinary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func processBlockTitle(for block: ConversationProcessBlockDTO) -> String {
        switch block.kind {
        case .thinking:
            return block.isComplete ? "Thinking" : "Thinking"
        case .webSearch:
            return "Web Search"
        case .webFetch:
            return "Web Fetch"
        }
    }

    private func processBlockPreviewText(for block: ConversationProcessBlockDTO) -> String {
        switch block.kind {
        case .thinking:
            let lines = block.text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            let previewLines = Array(lines.suffix(2))
            var preview = previewLines.joined(separator: "\n")
            if lines.count > 2 || !block.isComplete {
                preview += "..."
            }
            return preview
        case .webSearch, .webFetch:
            let lines = block.text.components(separatedBy: .newlines)
            return Array(lines.prefix(5)).joined(separator: "\n")
        }
    }
}

private struct ScreenshotThumbnailStrip: View {
    let screenshots: [CapturedScreenshot]

    private let visibleThumbnailCount = 3

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(screenshots.prefix(visibleThumbnailCount).enumerated()), id: \.element.id) { _, screenshot in
                ScreenshotThumbnail(screenshot: screenshot)
            }

            if screenshots.count > visibleThumbnailCount {
                Text("+\(screenshots.count - visibleThumbnailCount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.12))
                    )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ComposerContextShelf: View {
    let items: [ContextPreviewItem]
    let onRemove: (ContextPreviewItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    ComposerContextTile(item: item, onRemove: onRemove)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct ComposerContextTile: View {
    let item: ContextPreviewItem
    let onRemove: (ContextPreviewItem) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            tileBody

            Button {
                onRemove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.55))
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove context item")
        }
    }

    @ViewBuilder
    private var tileBody: some View {
        switch item {
        case let .screenshot(screenshot):
            ScreenshotThumbnail(screenshot: screenshot)
        case let .selectedText(selectionSnapshot):
            SelectedTextAttachmentTile(selectionSnapshot: selectionSnapshot)
        case let .browserPage(context):
            BrowserPageAttachmentTile(context: context)
        }
    }
}

private struct SelectedTextAttachmentTile: View {
    let selectionSnapshot: SelectedTextManager.SelectionSnapshot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)

            VStack(spacing: 6) {
                attachmentStripe(width: 76, opacity: 0.28)
                attachmentStripe(width: 66, opacity: 0.2)
                attachmentStripe(width: 82, opacity: 0.14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 11)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectionSnapshot.appName ?? "Selected Text")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("Text context")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 112, height: 56)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .help(selectionSnapshot.text)
    }

    private func attachmentStripe(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: width, height: 5)
    }
}

private struct BrowserPageAttachmentTile: View {
    let context: BrowserPageContext

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)

            VStack(spacing: 6) {
                attachmentStripe(width: 80, opacity: 0.28)
                attachmentStripe(width: 60, opacity: 0.2)
                attachmentStripe(width: 70, opacity: 0.14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 11)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.displayDomain)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("Web page")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 112, height: 56)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .help(context.pageTitle)
    }

    private func attachmentStripe(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: width, height: 5)
    }
}

private struct ScreenshotThumbnail: View {
    let screenshot: CapturedScreenshot

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: screenshot.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }
}

private struct ContextStackPreviewCard: View {
    let item: ContextPreviewItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardBackground

            if showsCaption {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.18), .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(.rect(cornerRadius: 24))

                cardCaption
                    .padding(14)
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(.rect(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.ultraThinMaterial, lineWidth: 5)
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch item {
        case let .screenshot(screenshot):
            if let image = NSImage(contentsOf: screenshot.fileURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
        case let .selectedText(selectionSnapshot):
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .background(.regularMaterial)

                Image(systemName: "text.quote")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(16)

                Text(selectionSnapshot.text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 50)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case let .browserPage(context):
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .background(.regularMaterial)

                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(16)

                Text(context.pageTitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 50)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var cardCaption: some View {
        switch item {
        case .screenshot:
            EmptyView()
        case let .selectedText(selectionSnapshot):
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSnapshot.appName ?? "Selected Text")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text("Text selection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.trailing, 18)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case let .browserPage(context):
            VStack(alignment: .leading, spacing: 2) {
                Text(context.displayDomain)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text("Web page")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.trailing, 18)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var showsCaption: Bool {
        switch item {
        case .screenshot:
            return false
        case .selectedText:
            return true
        case let .browserPage(context):
            return !context.displayDomain.isEmpty
        }
    }
}

// MARK: - Composer input

private struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = FirstMouseTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = context.coordinator
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.cell?.truncatesLastVisibleLine = false
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape

        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }

        if textField.stringValue != text {
            if text.isEmpty {
                applyText(text, to: textField)
            } else if context.coordinator.shouldApplyExternalTextUpdate(for: textField) {
                textField.stringValue = text
            }
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            textField.window?.makeKey()
            textField.window?.makeFirstResponder(textField)
        }
    }

    private func applyText(_ text: String, to textField: NSTextField) {
        if let editor = textField.currentEditor() as? NSTextView {
            editor.string = text
        }
        textField.stringValue = text
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onEscape: () -> Void
        var lastFocusRequestID: UUID?

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onEscape: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func shouldApplyExternalTextUpdate(for textField: NSTextField) -> Bool {
            guard let editor = textField.currentEditor() else {
                return true
            }

            return textField.window?.firstResponder !== editor
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }

            if commandSelector == #selector(NSText.selectAll(_:)) {
                textView.selectAll(nil)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onEscape()
                return true
            }

            return false
        }
    }
}

private final class FirstMouseTextField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            if let editor = currentEditor() {
                editor.selectAll(nil)
                return true
            }

            selectText(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Window drag handle

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

private final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}