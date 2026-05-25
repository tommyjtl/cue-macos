import AppKit
import Foundation

@MainActor
final class ContextSession {
    struct Snapshot {
        var capturedScreenshots: [CapturedScreenshot] = []
        var selectedTextContexts: [AttachedTextContext] = []
        var browserPageContexts: [BrowserPageContext] = []
        var isCaptureInProgress = false
    }

    private let onSnapshotChange: @MainActor (Snapshot) -> Void
    private var captureCoordinator: CaptureCoordinator?
    private var snapshot = Snapshot()

    init(onSnapshotChange: @escaping @MainActor (Snapshot) -> Void) {
        self.onSnapshotChange = onSnapshotChange
        publishSnapshot()
    }

    func clear() {
        snapshot.capturedScreenshots.removeAll()
        snapshot.selectedTextContexts.removeAll()
        snapshot.browserPageContexts.removeAll()
        snapshot.isCaptureInProgress = false
        publishSnapshot()
    }

    func removeScreenshot(id: UUID) {
        snapshot.capturedScreenshots.removeAll { $0.id == id }
        publishSnapshot()
    }

    func removeSelectedTextContext(createdAt: Date) {
        snapshot.selectedTextContexts.removeAll { $0.createdAt == createdAt }
        publishSnapshot()
    }

    func addBrowserPage(_ context: BrowserPageContext) {
        guard !snapshot.browserPageContexts.contains(where: { $0.url == context.url }) else {
            return
        }
        snapshot.browserPageContexts.insert(context, at: 0)
        publishSnapshot()
    }

    func removeBrowserPage(id: UUID) {
        snapshot.browserPageContexts.removeAll { $0.id == id }
        publishSnapshot()
    }

    func containsBrowserPage(url: String) -> Bool {
        snapshot.browserPageContexts.contains { $0.url == url }
    }

    @discardableResult
    func attachClipboardText(_ text: String, frontmostApplication: NSRunningApplication?) -> Bool {
        let attachedText = AttachedTextContext(
            createdAt: Date(),
            text: text,
            appName: frontmostApplication?.localizedName,
            bundleIdentifier: frontmostApplication?.bundleIdentifier
        )

        if let latestSelection = snapshot.selectedTextContexts.first,
           latestSelection.isEquivalent(to: attachedText) {
            return false
        }

        snapshot.selectedTextContexts.insert(attachedText, at: 0)
        publishSnapshot()
        return true
    }

    func beginScreenshotCapture(
        setStatus: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (String?) -> Void,
        onCaptureSaved: @escaping @MainActor (CapturedScreenshot) -> Void
    ) {
        guard !snapshot.isCaptureInProgress else {
            return
        }

        snapshot.isCaptureInProgress = true
        publishSnapshot()
        setError(nil)
        setStatus("Select a region to capture. Press Escape to cancel.")

        if captureCoordinator == nil {
            captureCoordinator = CaptureCoordinator()
        }

        Task { @MainActor in
            defer {
                snapshot.isCaptureInProgress = false
                publishSnapshot()
            }

            do {
                guard let captureCoordinator else {
                    throw CaptureError.captureFailed
                }

                let screenshot = try await captureCoordinator.beginCapture()
                snapshot.capturedScreenshots.insert(screenshot, at: 0)
                publishSnapshot()
                onCaptureSaved(screenshot)
                setStatus("Saved screenshot to \(screenshot.fileName).")
            } catch CaptureError.selectionCancelled {
                setStatus("Capture cancelled.")
            } catch {
                setError(error.localizedDescription)
                setStatus("Capture failed.")
            }
        }
    }

    private func publishSnapshot() {
        onSnapshotChange(snapshot)
    }
}
