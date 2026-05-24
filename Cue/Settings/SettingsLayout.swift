import AppKit
import SwiftUI

enum SettingsLayout {
    static let pagePadding: CGFloat = 36
    static let pageMaxWidth: CGFloat = 680
    static let sectionSpacing: CGFloat = 24
    static let cardCornerRadius: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 20
    static let rowVerticalPadding: CGFloat = 16

    enum MainWindow {
        static let defaultWidth: CGFloat = 960
        static let defaultHeight: CGFloat = 680
        static let minWidth: CGFloat = defaultWidth
        static let minHeight: CGFloat = 520
    }

    static var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.16, alpha: 1)
            }
            return NSColor(red: 0.969, green: 0.961, blue: 0.945, alpha: 1)
        })
    }

    static var changeButtonBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.24, alpha: 1)
            }
            return NSColor(red: 0.937, green: 0.922, blue: 0.898, alpha: 1)
        })
    }

    static var insetBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(white: 0.12, alpha: 1)
            }
            return NSColor(red: 0.992, green: 0.988, blue: 0.980, alpha: 1)
        })
    }
}

struct SettingsPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            SettingsLayout.cardBackground,
            in: RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
        )
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsLayout.rowHorizontalPadding)
    }
}

struct SettingsChangeButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String = "Change", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(SettingsChangeButtonStyle())
    }
}

struct SettingsChangeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                SettingsLayout.changeButtonBackground.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .foregroundStyle(.primary)
    }
}

struct SettingsInsetContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.bottom, SettingsLayout.rowVerticalPadding)
        .padding(.top, 4)
        .background(SettingsLayout.insetBackground)
    }
}

struct SettingsCardBody<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsFieldGroup<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct SettingsDetailScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                SettingsPageHeader(title: title, subtitle: subtitle)

                content
            }
            .padding(SettingsLayout.pagePadding)
            .frame(maxWidth: SettingsLayout.pageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
