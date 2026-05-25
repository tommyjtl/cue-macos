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
        reason: "Cue listens for global shortcuts like double Option and double ⌘C. Accessibility is required for those shortcuts to work in other apps.",
        grantLabel: "Allow Accessibility"
    )

    static let all: [PermissionItem] = [.screenRecording, .accessibility]
}

// MARK: - Onboarding Sheet

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel

    private let permissionManager = PermissionManager.shared

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
        .task {
            await appModel.refreshPermissions()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await appModel.refreshPermissions()
            }
        }
        .task {
            while !Task.isCancelled {
                await appModel.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
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
        case .screenRecording: appModel.screenRecordingGranted
        case .accessibility: appModel.accessibilityGranted
        }
    }

    private func grant(_ item: PermissionItem) {
        switch item.id {
        case .screenRecording:
            Task {
                await permissionManager.requestScreenCapturePermission()
                await appModel.refreshPermissions()
            }
        case .accessibility:
            permissionManager.requestAccessibilityPermission()
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await appModel.refreshPermissions()
            }
        }
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
