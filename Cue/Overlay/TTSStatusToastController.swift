import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
@Observable
final class TTSStatusToastViewModel {
    var title = ""
    var subtitle: String?
}

struct TTSStatusToastView: View {
    @Bindable var model: TTSStatusToastViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minWidth: 220, maxWidth: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

@MainActor
final class TTSStatusToastController {
    private enum Layout {
        static let panelSize = NSSize(width: 280, height: 72)
        static let errorDismissDelay: Duration = .seconds(3.5)
        static let cursorOffset = OverlayPlacement.ttsToastCursorOffset
    }

    private let viewModel = TTSStatusToastViewModel()
    private let panel: NSPanel
    private let hostingView: NSHostingView<TTSStatusToastView>
    private var displayLink: CADisplayLink?
    private var dismissTask: Task<Void, Never>?

    init() {
        hostingView = NSHostingView(
            rootView: TTSStatusToastView(model: viewModel)
        )

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hostingView
    }

    func showError(
        title: String,
        subtitle: String? = nil,
        near point: NSPoint = NSEvent.mouseLocation
    ) {
        dismissTask?.cancel()
        viewModel.title = title
        viewModel.subtitle = subtitle
        present(near: point)

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: Layout.errorDismissDelay)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        stopFollowingCursor()
        panel.orderOut(nil)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    private func present(near point: NSPoint) {
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize
        let panelSize = NSSize(
            width: max(Layout.panelSize.width, contentSize.width),
            height: max(56, contentSize.height)
        )
        panel.setContentSize(panelSize)

        let origin = OverlayPlacement.clampedOrigin(
            for: panelSize,
            near: point,
            cursorOffset: Layout.cursorOffset
        )
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        startFollowingCursor()
    }

    private func startFollowingCursor() {
        guard displayLink == nil else { return }

        let link = panel.displayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopFollowingCursor() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func handleDisplayLinkTick(_ sender: CADisplayLink) {
        guard panel.isVisible else {
            stopFollowingCursor()
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let targetOrigin = OverlayPlacement.clampedOrigin(
            for: panel.frame.size,
            near: mouseLocation,
            cursorOffset: Layout.cursorOffset
        )
        guard abs(panel.frame.origin.x - targetOrigin.x) > 0.5
            || abs(panel.frame.origin.y - targetOrigin.y) > 0.5 else {
            return
        }

        panel.setFrameOrigin(targetOrigin)
    }
}

enum TTSStatusToastCopy {
    static func errorPresentation(for message: String) -> (title: String, subtitle: String?) {
        if message.contains("not running") || message.contains("backend") {
            return (
                "TTS backend isn't running.",
                "Start cue-tts-backend-experiment, then try again."
            )
        }

        return (message, nil)
    }
}
