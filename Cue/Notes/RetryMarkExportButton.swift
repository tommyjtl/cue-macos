import SwiftUI

struct RetryMarkExportButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .help("Try generating the bookmark again")
    }
}
