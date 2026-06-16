import SwiftUI
import Textual

struct SearchResultMessageView: View {
    let answer: String
    let sources: [SearchResultSource]

    @State private var selectedSourceIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StructuredText(markdown: answer)
                .textual.structuredTextStyle(.default)
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let source = selectedSource {
                VStack(alignment: .leading, spacing: 10) {
                    sourcesHeader

                    sourceCard(source)
                }
            }
        }
        .onChange(of: sources.count) { _, _ in
            selectedSourceIndex = 0
        }
    }

    private var selectedSource: SearchResultSource? {
        guard !sources.isEmpty,
              sources.indices.contains(selectedSourceIndex) else {
            return nil
        }
        return sources[selectedSourceIndex]
    }

    private var sourcesHeader: some View {
        HStack(spacing: 8) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if sources.count > 1 {
                Text("\(selectedSourceIndex + 1) / \(sources.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if sources.count > 1 {
                HStack(spacing: 4) {
                    carouselButton(
                        systemImage: "chevron.left",
                        help: "Previous source",
                        isEnabled: selectedSourceIndex > 0
                    ) {
                        selectedSourceIndex -= 1
                    }

                    carouselButton(
                        systemImage: "chevron.right",
                        help: "Next source",
                        isEnabled: selectedSourceIndex < sources.count - 1
                    ) {
                        selectedSourceIndex += 1
                    }
                }
            }
        }
    }

    private func carouselButton(
        systemImage: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .secondary : .tertiary)
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
        .help(help)
    }

    private func sourceCard(_ source: SearchResultSource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if !source.section.isEmpty {
                Text(source.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !source.excerpt.isEmpty {
                Text(source.excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            OpenObsidianNoteButton(fileURL: URL(fileURLWithPath: source.filePath))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .id(selectedSourceIndex)
        .transition(.opacity)
    }
}
