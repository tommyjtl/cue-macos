import AppKit
import Observation
import QuartzCore
import SwiftUI

enum TTSActivityPhase: Equatable {
    case generating
    case speaking
}

@MainActor
@Observable
final class TTSActivityIndicatorViewModel {
    var phase: TTSActivityPhase = .generating
}

struct TTSActivityIndicatorView: View {
    let phase: TTSActivityPhase

    private enum Layout {
        static let frameSize: CGFloat = 18
        static let iconSize: CGFloat = 12
    }

    var body: some View {
        TTSOutlinedSymbol(name: iconName, size: Layout.iconSize)
            .frame(width: Layout.frameSize, height: Layout.frameSize)
            .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch phase {
        case .generating:
            "clock"
        case .speaking:
            "speaker.wave.3.fill"
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .generating:
            "Generating speech"
        case .speaking:
            "Speaking selected text"
        }
    }
}

private struct TTSOutlinedSymbol: View {
    let name: String
    let size: CGFloat

    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -0.55, height: 0),
        CGSize(width: 0.55, height: 0),
        CGSize(width: 0, height: -0.55),
        CGSize(width: 0, height: 0.55),
        CGSize(width: -0.4, height: -0.4),
        CGSize(width: 0.4, height: -0.4),
        CGSize(width: -0.4, height: 0.4),
        CGSize(width: 0.4, height: 0.4),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.outlineOffsets.enumerated()), id: \.offset) { _, offset in
                Image(systemName: name)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: offset.width, y: offset.height)
            }

            Image(systemName: name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.black)
                .symbolRenderingMode(.monochrome)
        }
    }
}

@MainActor
final class TTSActivityIndicatorController {
    private enum Layout {
        static let panelSize = NSSize(width: 18, height: 18)
    }

    private let viewModel = TTSActivityIndicatorViewModel()
    private let panel: NSPanel
    private let hostingView: NSHostingView<TTSActivityIndicatorView>
    private var displayLink: CADisplayLink?

    init() {
        hostingView = NSHostingView(
            rootView: TTSActivityIndicatorView(phase: viewModel.phase)
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

    func showGenerating(near point: NSPoint = NSEvent.mouseLocation) {
        show(phase: .generating, near: point)
    }

    func showSpeaking(near point: NSPoint = NSEvent.mouseLocation) {
        show(phase: .speaking, near: point)
    }

    func hide() {
        stopFollowingCursor()
        panel.orderOut(nil)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    private func show(phase: TTSActivityPhase, near point: NSPoint) {
        viewModel.phase = phase
        hostingView.rootView = TTSActivityIndicatorView(phase: phase)
        present(near: point)
    }

    private func present(near point: NSPoint) {
        panel.setContentSize(Layout.panelSize)

        let origin = OverlayPlacement.clampedOriginTopTrailing(
            for: Layout.panelSize,
            near: point
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
        let targetOrigin = OverlayPlacement.clampedOriginTopTrailing(
            for: panel.frame.size,
            near: mouseLocation
        )
        guard abs(panel.frame.origin.x - targetOrigin.x) > 0.5
            || abs(panel.frame.origin.y - targetOrigin.y) > 0.5 else {
            return
        }

        panel.setFrameOrigin(targetOrigin)
    }
}
