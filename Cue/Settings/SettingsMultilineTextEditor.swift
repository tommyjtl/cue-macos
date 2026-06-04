import AppKit
import SwiftUI

struct SettingsMultilineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12
    var minHeight: CGFloat = 140
    var resetGeneration: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SettingsTextView()
        textView.delegate = context.coordinator
        textView.onEditingChanged = { isEditing in
            context.coordinator.isEditing = isEditing
        }
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SettingsTextView else {
            return
        }

        context.coordinator.textView = textView

        if context.coordinator.lastAppliedResetGeneration != resetGeneration {
            context.coordinator.lastAppliedResetGeneration = resetGeneration
            applyExternalText(text, to: textView, coordinator: context.coordinator)
            return
        }

        guard !context.coordinator.shouldSkipExternalTextUpdate(for: textView) else {
            return
        }

        if textView.string != text {
            applyExternalText(text, to: textView, coordinator: context.coordinator)
        }
    }

    private func applyExternalText(_ value: String, to textView: NSTextView, coordinator: Coordinator) {
        guard textView.string != value else {
            return
        }

        coordinator.isApplyingExternalText = true
        textView.string = value
        coordinator.isApplyingExternalText = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isEditing = false
        var isApplyingExternalText = false
        var lastAppliedResetGeneration = 0
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func shouldSkipExternalTextUpdate(for textView: NSTextView) -> Bool {
            if isEditing {
                return true
            }

            if textView.window?.firstResponder === textView {
                return true
            }

            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }
}

struct SettingsReadOnlyTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 12
    var minHeight: CGFloat = 120

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SettingsTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SettingsTextView,
              textView.string != text else {
            return
        }

        textView.string = text
    }
}

private final class SettingsTextView: NSTextView {
    var onEditingChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onEditingChanged?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onEditingChanged?(false)
        }
        return didResignFirstResponder
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
}
