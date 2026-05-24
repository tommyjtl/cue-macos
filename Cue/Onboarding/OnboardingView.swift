import AppKit
import SwiftUI

// MARK: - Model

struct PermissionItem: Identifiable {
    enum Kind { case screenRecording, accessibility }

    let id: Kind
    let systemImage: String
    let title: String
    let reason: String
    let grantLabel: String
}

extension PermissionItem {
    static let screenRecording = PermissionItem(
        id: .screenRecording,
        systemImage: "rectangle.dashed.badge.record",
        title: "Screen Recording",
        reason: "Cue captures a region of your screen when you trigger a screenshot context. Nothing is recorded automatically — capture only happens when you explicitly invoke it.",
        grantLabel: "Allow Screen Recording"
    )

    static let accessibility = PermissionItem(
        id: .accessibility,
        systemImage: "accessibility",
        title: "Accessibility",
        reason: "Cue reads the text you have selected in other apps so you can attach it to a conversation without copying and pasting. Accessibility is also required to detect the global capture shortcut.",
        grantLabel: "Allow Accessibility"
    )

    static let all: [PermissionItem] = [.screenRecording, .accessibility]
}

// MARK: - Onboarding Sheet

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    private let permissionManager = PermissionManager()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(PermissionItem.all) { item in
                        PermissionRowView(
                            item: item,
                            isGranted: isGranted(item),
                            onGrant: { grant(item) }
                        )
                    }
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(width: 480)
        .onAppear { refreshStatus() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                refreshStatus()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshStatus()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Welcome to Cue")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Cue needs a couple of permissions to work. You can also grant these later from Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Continue") {
                appModel.completeOnboarding()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    // MARK: Helpers

    private func isGranted(_ item: PermissionItem) -> Bool {
        switch item.id {
        case .screenRecording: screenRecordingGranted
        case .accessibility: accessibilityGranted
        }
    }

    private func grant(_ item: PermissionItem) {
        switch item.id {
        case .screenRecording:
            // Use an SCK API call \u2014 this is what registers the app in the
            // System Settings Screen Recording list on macOS 14+.
            Task {
                await permissionManager.requestScreenCaptureViaScreenCaptureKit()
                screenRecordingGranted = permissionManager.hasScreenCapturePermission()
            }
        case .accessibility:
            let granted = permissionManager.ensureAccessibilityPermission(promptIfNeeded: true)
            accessibilityGranted = granted
            if !granted {
                permissionManager.openAccessibilitySettings()
            }
        }
    }

    private func refreshStatus() {
        screenRecordingGranted = permissionManager.hasScreenCapturePermission()
        accessibilityGranted = permissionManager.hasAccessibilityPermission()
    }
}

// MARK: - Permission Row

private struct PermissionRowView: View {
    let item: PermissionItem
    let isGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.systemImage)
                .font(.system(size: 24))
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)

                    Spacer()

                    if isGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button(item.grantLabel, action: onGrant)
                            .controlSize(.small)
                    }
                }

                Text(item.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
