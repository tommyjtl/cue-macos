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
    var selectedTextContexts: [AttachedTextContext] = []
    var browserPageContexts: [BrowserPageContext] = []
    var messages: [ConversationMessageDTO] = []
    var mode: Mode = .stack
    var draftMessage = ""
    var isSending = false
    var canCancelSend = false
    var inFlightActivity: ComposerInFlightActivity = .none
    var conversationProvider: ConversationProvider = .ollama
    var providerDisplayName = ""
    var composerFocusRequestID = UUID()
    /// 1 = compact composer; 2 = expanded (two visible lines).
    var composerVisibleLineCount = 1
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

    private enum ComposerLayout {
        static let controlFont = Font.system(size: 13)
        static let controlFontSize: CGFloat = 13
        static let cornerRadius: CGFloat = 14
        static let headerHeight: CGFloat = 44
        static func composerEditorHeight(
            fontSize: CGFloat = controlFontSize,
            visibleLineCount: Int = 1
        ) -> CGFloat {
            ComposerInputMetrics.editorHeight(fontSize: fontSize, visibleLineCount: visibleLineCount)
        }
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
            chatHeader

            transcriptContent

            if !contextPreviewItems.isEmpty {
                ComposerContextShelf(items: contextPreviewItems, onRemove: onRemoveContextItem)
            }

            ZStack(alignment: .topLeading) {
                ComposerTextField(
                    text: $model.draftMessage,
                    visibleLineCount: $model.composerVisibleLineCount,
                    fontSize: ComposerLayout.controlFontSize,
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

                if model.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(composerPlaceholder)
                        .font(ComposerLayout.controlFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, ComposerInputMetrics.placeholderHorizontalPadding)
                        .padding(.vertical, ComposerInputMetrics.textContainerVerticalInset)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: ComposerLayout.composerEditorHeight(visibleLineCount: model.composerVisibleLineCount))
            .animation(.easeInOut(duration: 0.15), value: model.composerVisibleLineCount)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ComposerLayout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ComposerLayout.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }

            HStack(alignment: .center) {
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.borderless)
                .font(ComposerLayout.controlFont)

                if model.messages.isEmpty && model.hasSavedConversations {
                    Button("Load recent chat") {
                        onLoadMostRecent()
                    }
                    .buttonStyle(.borderless)
                    .font(ComposerLayout.controlFont)
                }

                Spacer(minLength: 12)

                if model.supportsWebSearch {
                    HStack(spacing: 6) {
                        Toggle("Web Search", isOn: webSearchBinding)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help(model.isWebSearchEnabled ? "Disable web search for this provider" : "Enable web search for this provider")

                        Text("Web Search")
                            .font(ComposerLayout.controlFont)
                            .foregroundStyle(.secondary)
                    }
                }

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

    private var chatHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .leading) {
                WindowDragArea()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Cue")
                        .font(.headline)

                    Text(chatSubtitle)
                        .font(ComposerLayout.controlFont)
                        .foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

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
        .frame(height: ComposerLayout.headerHeight)
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.messages) { message in
                                ConversationMessageBubble(
                                    message: message,
                                    assistantDisplayName: assistantDisplayName,
                                    rendersStreamingText: model.isSending
                                        && !model.inFlightActivity.showsStatusBox
                                        && message.id == model.messages.last?.id
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

            if model.inFlightActivity.showsStatusBox {
                ComposerCommandStatusBox(activity: model.inFlightActivity)
            } else if model.isSending {
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
        let modeTitle = model.conversationProvider.title
        let modelName = model.providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            return modeTitle
        }

        return "\(modeTitle) • \(modelName)"
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
    case selectedText(AttachedTextContext)
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

private struct ComposerCommandStatusBox: View {
    let activity: ComposerInFlightActivity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(activity.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.65),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

            if let savedNoteFileURL = ObsidianSavedNoteMessage.savedNoteFileURL(from: message.text) {
                Text("Saved to Obsidian.")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                OpenObsidianNoteButton(fileURL: savedNoteFileURL)
                    .padding(.top, 4)
            } else if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        ClipboardMonitor.temporarilyIgnoreCopyShortcut()
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
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    ComposerContextTile(item: item, onRemove: onRemove)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.visible, axes: .horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            SelectedTextAttachmentTile(attachedText: selectionSnapshot)
        case let .browserPage(context):
            BrowserPageAttachmentTile(context: context)
        }
    }
}

private struct SelectedTextAttachmentTile: View {
    let attachedText: AttachedTextContext

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
                    Text(attachedText.appName ?? "Selected Text")
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
        .help(attachedText.text)
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

enum ComposerInputMetrics {
    static let compactVisibleLineCount = 1
    static let expandedVisibleLineCount = 2
    static let chatPanelWidth: CGFloat = 360
    static let chatPanelHorizontalPadding: CGFloat = 14
    static let expandThresholdMultiplier: CGFloat = 1.05
    static let collapseThresholdMultiplier: CGFloat = 0.95
    /// Inset applied on each vertical edge of the text view (top and bottom).
    static let textContainerVerticalInset: CGFloat = 8
    static let textContainerHorizontalInset: CGFloat = 6
    /// Extra chrome beyond line metrics + insets so text/placeholder sit visually centered.
    static let extraVerticalChrome: CGFloat = 0 // was 4
    static var textContainerInset: NSSize {
        NSSize(width: textContainerHorizontalInset, height: textContainerVerticalInset)
    }

    static var placeholderHorizontalPadding: CGFloat {
        textContainerHorizontalInset + 8
    }

    static var totalVerticalTextInset: CGFloat {
        textContainerVerticalInset * 2
    }

    static var fallbackLayoutWidth: CGFloat {
        chatPanelWidth - (chatPanelHorizontalPadding * 2)
    }

    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
    }

    /// Visible text viewport inside the composer chrome (lines × line height + insets).
    static func textViewportHeight(fontSize: CGFloat, visibleLineCount: Int) -> CGFloat {
        let clampedLines = clampedVisibleLineCount(visibleLineCount)
        return lineHeight(fontSize: fontSize) * CGFloat(clampedLines)
            + totalVerticalTextInset
            + extraVerticalChrome
    }

    /// Total SwiftUI frame height for the composer `ZStack` in chat mode.
    static func editorHeight(fontSize: CGFloat, visibleLineCount: Int) -> CGFloat {
        textViewportHeight(fontSize: fontSize, visibleLineCount: visibleLineCount)
    }

    static func clampedVisibleLineCount(_ count: Int) -> Int {
        min(max(count, compactVisibleLineCount), expandedVisibleLineCount)
    }

    static func stableLayoutWidth(contentViewWidth: CGFloat) -> CGFloat {
        let measuredWidth = max(contentViewWidth, 1)
        if measuredWidth >= fallbackLayoutWidth * 0.9 {
            return measuredWidth
        }
        return fallbackLayoutWidth
    }

    static func resolvedLineTier(
        isEmpty: Bool,
        hasExplicitNewline: Bool,
        lineFragmentCount: Int,
        usedHeight: CGFloat,
        singleLineHeight: CGFloat,
        currentVisibleLineCount: Int
    ) -> Int {
        guard !isEmpty else {
            return compactVisibleLineCount
        }

        if hasExplicitNewline || lineFragmentCount >= 2 {
            return expandedVisibleLineCount
        }

        let expandThreshold = singleLineHeight * expandThresholdMultiplier
        let collapseThreshold = singleLineHeight * collapseThresholdMultiplier

        if clampedVisibleLineCount(currentVisibleLineCount) >= expandedVisibleLineCount {
            return usedHeight > collapseThreshold ? expandedVisibleLineCount : compactVisibleLineCount
        }

        return usedHeight > expandThreshold ? expandedVisibleLineCount : compactVisibleLineCount
    }

    /// 1 = single-line chrome; 2 = two-line chrome (wraps or explicit newline).
    static func displayedLineTier(
        for textView: NSTextView,
        fontSize: CGFloat,
        layoutWidth: CGFloat,
        currentVisibleLineCount: Int
    ) -> Int {
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return compactVisibleLineCount
        }

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return clampedVisibleLineCount(currentVisibleLineCount)
        }

        let width = max(layoutWidth, 1)
        let savedContainerSize = textContainer.containerSize
        defer {
            textContainer.containerSize = savedContainerSize
            layoutManager.ensureLayout(for: textContainer)
        }

        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineFragmentCount = 0
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
                lineFragmentCount += 1
            }
        }

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let singleLineHeight = lineHeight(fontSize: fontSize)
        let hasExplicitNewline = trimmed.contains(where: \.isNewline)

        return resolvedLineTier(
            isEmpty: false,
            hasExplicitNewline: hasExplicitNewline,
            lineFragmentCount: lineFragmentCount,
            usedHeight: usedHeight,
            singleLineHeight: singleLineHeight,
            currentVisibleLineCount: currentVisibleLineCount
        )
    }
}

private struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var visibleLineCount: Int
    let fontSize: CGFloat
    let focusRequestID: UUID
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            visibleLineCount: $visibleLineCount,
            fontSize: fontSize,
            onSubmit: onSubmit,
            onEscape: onEscape
        )
    }

    func makeNSView(context: Context) -> ComposerInputScrollView {
        let scrollView = ComposerInputScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.viewportHeight = ComposerInputMetrics.textViewportHeight(
            fontSize: fontSize,
            visibleLineCount: visibleLineCount
        )

        let textView = ComposerInputTextView()
        textView.onSubmit = { context.coordinator.onSubmit() }
        textView.onEscape = { context.coordinator.onEscape() }
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = ComposerInputMetrics.textContainerInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.lineBreakMode = .byWordWrapping
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        scrollView.onAfterLayout = { [coordinator = context.coordinator] textView in
            coordinator.updateVisibleLineCount(for: textView)
        }
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        scrollView.refreshTextViewLayout()

        return scrollView
    }

    func updateNSView(_ scrollView: ComposerInputScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape

        let viewportHeight = ComposerInputMetrics.textViewportHeight(
            fontSize: fontSize,
            visibleLineCount: visibleLineCount
        )
        scrollView.onAfterLayout = { [coordinator = context.coordinator] textView in
            coordinator.updateVisibleLineCount(for: textView)
        }
        if scrollView.viewportHeight != viewportHeight {
            scrollView.viewportHeight = viewportHeight
        }

        guard let textView = context.coordinator.textView else {
            return
        }

        textView.onSubmit = { context.coordinator.onSubmit() }
        textView.onEscape = { context.coordinator.onEscape() }

        let font = NSFont.systemFont(ofSize: fontSize)
        if textView.font != font {
            textView.font = font
        }

        if textView.string != text {
            if text.isEmpty {
                context.coordinator.applyText(text, to: textView)
            } else if context.coordinator.shouldApplyExternalTextUpdate(for: textView) {
                context.coordinator.applyText(text, to: textView)
            }
        } else if !context.coordinator.isApplyingHighlight,
                  let font = textView.font {
            context.coordinator.applySlashCommandHighlighting(to: textView, text: textView.string, font: font)
        }

        scrollView.refreshTextViewLayout()

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            textView.window?.makeKey()
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var visibleLineCount: Int
        let fontSize: CGFloat
        var onSubmit: () -> Void
        var onEscape: () -> Void
        var lastFocusRequestID: UUID?
        weak var textView: ComposerInputTextView?
        weak var scrollView: ComposerInputScrollView?
        var isApplyingHighlight = false

        init(
            text: Binding<String>,
            visibleLineCount: Binding<Int>,
            fontSize: CGFloat,
            onSubmit: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            _text = text
            _visibleLineCount = visibleLineCount
            self.fontSize = fontSize
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func shouldApplyExternalTextUpdate(for textView: NSTextView) -> Bool {
            if textView.hasMarkedText() {
                return false
            }

            return textView.window?.firstResponder !== textView
        }

        func applyText(_ value: String, to textView: NSTextView) {
            let normalizedValue = ComposerCommandTextNormalizer.normalizeComposerDraft(value)
            guard textView.string != normalizedValue else {
                return
            }

            if normalizedValue.isEmpty {
                textView.string = ""
                textView.undoManager?.removeAllActions()
                textView.scrollToBeginningOfDocument(nil)
                updateVisibleLineCount(for: textView)
            } else if let font = textView.font {
                applySlashCommandHighlighting(to: textView, text: normalizedValue, font: font)
            } else {
                textView.string = normalizedValue
            }

            scrollView?.refreshTextViewLayout()
        }

        func updateVisibleLineCount(for textView: NSTextView) {
            let layoutWidth = scrollView?.stableTextLayoutWidth ?? ComposerInputMetrics.fallbackLayoutWidth
            let tier = ComposerInputMetrics.displayedLineTier(
                for: textView,
                fontSize: fontSize,
                layoutWidth: layoutWidth,
                currentVisibleLineCount: visibleLineCount
            )
            let clamped = ComposerInputMetrics.clampedVisibleLineCount(tier)
            guard visibleLineCount != clamped else {
                return
            }

            visibleLineCount = clamped

            let viewportHeight = ComposerInputMetrics.textViewportHeight(
                fontSize: fontSize,
                visibleLineCount: clamped
            )
            if scrollView?.viewportHeight != viewportHeight {
                scrollView?.viewportHeight = viewportHeight
            }
        }

        func applySlashCommandHighlighting(to textView: NSTextView, text: String, font: NSFont) {
            isApplyingHighlight = true
            ComposerSlashCommandHighlighter.apply(to: textView, text: text, font: font)
            isApplyingHighlight = false
            scrollView?.refreshTextViewLayout()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight,
                  let textView = notification.object as? NSTextView else {
                return
            }

            let originalValue = textView.string
            let selectedRange = textView.selectedRange()
            let normalization = ComposerCommandTextNormalizer.normalizingComposerDraftIfNeeded(originalValue)

            if normalization.didReplace {
                isApplyingHighlight = true
                text = normalization.text
                if let font = textView.font {
                    ComposerSlashCommandHighlighter.apply(
                        to: textView,
                        text: normalization.text,
                        font: font
                    )
                } else {
                    textView.string = normalization.text
                }
                let adjustedRange = ComposerCommandTextNormalizer.adjustedSelectedRange(
                    originalRange: selectedRange,
                    originalText: originalValue,
                    normalizedText: normalization.text
                )
                textView.setSelectedRange(adjustedRange)
                isApplyingHighlight = false
                updateVisibleLineCount(for: textView)
                scrollView?.refreshTextViewLayout()
                return
            }

            text = originalValue

            guard let font = textView.font else {
                scrollView?.refreshTextViewLayout()
                return
            }

            applySlashCommandHighlighting(to: textView, text: originalValue, font: font)
        }
    }
}

final class ComposerInputScrollView: NSScrollView {
    private var isRefreshingLayout = false
    var onAfterLayout: ((NSTextView) -> Void)?

    var stableTextLayoutWidth: CGFloat {
        ComposerInputMetrics.stableLayoutWidth(contentViewWidth: contentView.bounds.width)
    }

    var viewportHeight: CGFloat = 40 {
        didSet {
            if oldValue != viewportHeight {
                invalidateIntrinsicContentSize()
                refreshTextViewLayout()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: viewportHeight)
    }

    override func scrollWheel(with event: NSEvent) {
        if let textView = documentView {
            let contentHeight = textView.frame.height
            let visibleHeight = contentView.bounds.height
            if contentHeight <= visibleHeight + 1 {
                nextResponder?.scrollWheel(with: event)
                return
            }
        }

        super.scrollWheel(with: event)
    }

    func refreshTextViewLayout() {
        guard !isRefreshingLayout,
              let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        isRefreshingLayout = true
        defer { isRefreshingLayout = false }

        let width = stableTextLayoutWidth
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let verticalInset = textView.textContainerInset.height * 2
        let contentHeight = max(usedRect.height + verticalInset, viewportHeight)

        var frame = textView.frame
        frame.origin = .zero
        frame.size.width = width
        frame.size.height = contentHeight
        textView.frame = frame
        reflectScrolledClipView(contentView)
        onAfterLayout?(textView)
    }

    override func layout() {
        super.layout()
        refreshTextViewLayout()
    }
}

final class ComposerInputTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if ComposerEditShortcut.perform(with: event, sender: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleComposerKey(event) {
            return
        }

        super.keyDown(with: event)
    }

    private func handleComposerKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: // Return and keypad Enter (insertNewline on NSTextField)
            let shiftPressed = event.modifierFlags.contains(.shift)
            if !shiftPressed {
                onSubmit?()
                return true
            }
            return false
        case 53:
            onEscape?()
            return true
        default:
            return false
        }
    }
}

// MARK: - Window drag handle

extension Notification.Name {
    static let overlayPanelUserDidDrag = Notification.Name("cue.overlayPanelUserDidDrag")
}

enum OverlayPanelDragNotification {
    static let isDraggingKey = "isDragging"
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var isFlipped: Bool { true }

    private var isDragging = false
    private var dragOriginScreenLocation: NSPoint?
    private var dragOriginWindowFrame: NSRect?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !isDragging else {
            NSCursor.closedHand.set()
            return
        }

        NSCursor.openHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.openHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }

        isDragging = true
        dragOriginScreenLocation = NSEvent.mouseLocation
        dragOriginWindowFrame = window.frame
        window.invalidateCursorRects(for: self)
        NSCursor.closedHand.set()
        postDragNotification(for: window, isDragging: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging,
              let window,
              let originScreen = dragOriginScreenLocation,
              let originFrame = dragOriginWindowFrame else {
            return
        }

        let currentScreen = NSEvent.mouseLocation
        let deltaX = currentScreen.x - originScreen.x
        let deltaY = currentScreen.y - originScreen.y
        var newFrame = originFrame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        window.setFrame(newFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }

        isDragging = false
        dragOriginScreenLocation = nil
        dragOriginWindowFrame = nil
        window?.invalidateCursorRects(for: self)
        NSCursor.openHand.set()

        if let window {
            postDragNotification(for: window, isDragging: false)
        }
    }

    private func postDragNotification(for window: NSWindow, isDragging: Bool) {
        NotificationCenter.default.post(
            name: .overlayPanelUserDidDrag,
            object: window,
            userInfo: [OverlayPanelDragNotification.isDraggingKey: isDragging]
        )
    }
}