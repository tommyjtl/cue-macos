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
    let isFocused: Bool
    var escapeCancelsRecording = true
    let onEvent: (NSEvent) -> Bool
    let onCancelRecording: () -> Void
    let onFocusChange: (Bool) -> Void

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
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: isRecording && isFocused ? Color.accentColor.opacity(0.22) : .clear, radius: 6, y: 1)
        .overlay {
            if isRecording {
                ShortcutRecorderEventCaptureView(
                    isRecording: true,
                    escapeCancelsRecording: escapeCancelsRecording,
                    onEvent: onEvent,
                    onCancelRecording: onCancelRecording,
                    onFocusChange: onFocusChange
                )
            }
        }
        .allowsHitTesting(isRecording)
    }

    private var borderColor: Color {
        guard isRecording else {
            return .primary.opacity(0.08)
        }

        return isFocused ? Color.accentColor : Color.accentColor.opacity(0.55)
    }

    private var borderWidth: CGFloat {
        guard isRecording else { return 1 }
        return isFocused ? 2 : 1.5
    }
}

struct ShortcutSettingInlineRow: View {
    let title: String
    let tokens: [String]
    let isRecording: Bool
    let isFocused: Bool
    let canCommit: Bool
    let isChangeDisabled: Bool
    var escapeCancelsRecording = true
    let onChange: () -> Void
    let onDone: () -> Void
    let onEvent: (NSEvent) -> Bool
    let onCancelRecording: () -> Void
    let onFocusChange: (Bool) -> Void

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
                    isFocused: isFocused,
                    escapeCancelsRecording: escapeCancelsRecording,
                    onEvent: onEvent,
                    onCancelRecording: onCancelRecording,
                    onFocusChange: onFocusChange
                )

                if isRecording {
                    SettingsChangeButton("Done", action: onDone)
                        .disabled(!canCommit)
                } else {
                    SettingsChangeButton("Change", action: onChange)
                        .disabled(isChangeDisabled)
                }
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
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderCaptureView {
        let view = ShortcutRecorderCaptureView()
        view.escapeCancelsRecording = escapeCancelsRecording
        view.onEvent = onEvent
        view.onCancelRecording = onCancelRecording
        view.onFocusChange = onFocusChange
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderCaptureView, context: Context) {
        nsView.escapeCancelsRecording = escapeCancelsRecording
        nsView.onEvent = onEvent
        nsView.onCancelRecording = onCancelRecording
        nsView.onFocusChange = onFocusChange
        nsView.setRecording(isRecording)
    }

    static func dismantleNSView(_ nsView: ShortcutRecorderCaptureView, coordinator: ()) {
        nsView.teardown()
    }
}

@MainActor
final class ShortcutRecorderCaptureView: NSView {
    var escapeCancelsRecording = true
    var onEvent: ((NSEvent) -> Bool)?
    var onCancelRecording: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    func setRecording(_ isRecording: Bool) {
        guard self.isRecording != isRecording else { return }
        self.isRecording = isRecording

        if isRecording {
            window?.makeFirstResponder(self)
        } else {
            teardown()
        }
    }

    func teardown() {
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        reportFocus(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isRecording else { return }
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            reportFocus(true)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            reportFocus(false)
        }
        return resignedFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53, escapeCancelsRecording {
            onCancelRecording?()
            return
        }

        _ = onEvent?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        _ = onEvent?(event)
    }

    private func reportFocus(_ isFocused: Bool) {
        onFocusChange?(isFocused)
    }
}
