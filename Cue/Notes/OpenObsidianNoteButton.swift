import SwiftUI

struct OpenObsidianNoteButton: View {
    let fileURL: URL

    var body: some View {
        Button {
            ObsidianNoteOpener.openInNewTab(fileURL: fileURL)
        } label: {
            Label("Open in Obsidian", systemImage: "note.text")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .help("Open this note in Obsidian in a new tab")
    }
}
