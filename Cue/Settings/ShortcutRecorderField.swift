import AppKit
import SwiftUI

struct ShortcutKeyChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                SettingsLayout.insetBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct ShortcutKeyPreviewDisplay: View {
    let tokens: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                ShortcutKeyChip(title: token)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 148, alignment: .leading)
        .background(
            SettingsLayout.insetBackground.opacity(0.85),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ShortcutSettingReadOnlyRow: View {
    let title: String
    let tokens: [String]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            ShortcutKeyPreviewDisplay(tokens: tokens)
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

struct ShortcutKeyPreview: View {
    let tokens: [String]
    let isRecording: Bool
    var escapeCancelsRecording = true
    let onEvent: (NSEvent) -> Bool
    let onCancelRecording: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tokens.isEmpty {
                Text(isRecording ? "Please type your key" : "—")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    ShortcutKeyChip(title: token)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 148, alignment: .leading)
        .background(
            SettingsLayout.insetBackground.opacity(isRecording ? 1 : 0.85),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isRecording ? Color.accentColor.opacity(0.85) : .primary.opacity(0.08), lineWidth: isRecording ? 1.5 : 1)
        }
        .overlay {
            if isRecording {
                ShortcutRecorderEventCaptureView(
                    isRecording: true,
                    escapeCancelsRecording: escapeCancelsRecording,
                    onEvent: onEvent,
                    onCancelRecording: onCancelRecording
                )
            }
        }
    }
}

struct ShortcutSettingInlineRow: View {
    let title: String
    let tokens: [String]
    let isRecording: Bool
    let isChangeDisabled: Bool
    var escapeCancelsRecording = true
    let onChange: () -> Void
    let onEvent: (NSEvent) -> Bool
    let onCancelRecording: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                ShortcutKeyPreview(
                    tokens: tokens,
                    isRecording: isRecording,
                    escapeCancelsRecording: escapeCancelsRecording,
                    onEvent: onEvent,
                    onCancelRecording: onCancelRecording
                )

                SettingsChangeButton("Change", action: onChange)
                    .disabled(isChangeDisabled)
            }
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

struct ShortcutRecorderEventCaptureView: NSViewRepresentable {
    let isRecording: Bool
    var escapeCancelsRecording = true
    let onEvent: (NSEvent) -> Bool
    let onCancelRecording: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderCaptureView {
        let view = ShortcutRecorderCaptureView()
        view.escapeCancelsRecording = escapeCancelsRecording
        view.onEvent = onEvent
        view.onCancelRecording = onCancelRecording
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderCaptureView, context: Context) {
        nsView.escapeCancelsRecording = escapeCancelsRecording
        nsView.onEvent = onEvent
        nsView.onCancelRecording = onCancelRecording
        nsView.setRecording(isRecording)
    }
}

@MainActor
final class ShortcutRecorderCaptureView: NSView {
    var escapeCancelsRecording = true
    var onEvent: ((NSEvent) -> Bool)?
    var onCancelRecording: (() -> Void)?
    private var isRecording = false
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func setRecording(_ isRecording: Bool) {
        guard self.isRecording != isRecording else { return }
        self.isRecording = isRecording

        if isRecording {
            window?.makeFirstResponder(self)
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            if escapeCancelsRecording {
                onCancelRecording?()
            } else if onEvent?(event) == true {
                return
            }
            return
        }

        if onEvent?(event) == true {
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        _ = onEvent?(event)
    }

    private func installMonitor() {
        removeMonitor()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                if self.escapeCancelsRecording {
                    self.onCancelRecording?()
                } else if self.onEvent?(event) == true {
                    return nil
                }
                return event
            }

            if self.onEvent?(event) == true {
                return nil
            }

            return event
        }
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
