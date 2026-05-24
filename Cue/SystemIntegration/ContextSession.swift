import Foundation

@MainActor
final class ContextSession {
    struct Snapshot {
        var capturedScreenshots: [CapturedScreenshot] = []
        var selectedTextContexts: [SelectedTextManager.SelectionSnapshot] = []
        var browserPageContexts: [BrowserPageContext] = []
        var isCaptureInProgress = false
    }

    private let onSnapshotChange: @MainActor (Snapshot) -> Void
    private let selectedTextManager = SelectedTextManager()
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
        // Deduplicate: if the same URL was already pushed in this session, skip it.
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

    /// Returns true if the URL is already attached to the current context.
    func containsBrowserPage(url: String) -> Bool {
        snapshot.browserPageContexts.contains { $0.url == url }
    }

    /// Returns true if the frontmost app currently has text selected, without modifying any state.
    func hasCurrentlySelectedText() -> Bool {
        (try? selectedTextManager.captureSelectedText(promptForPermission: false, loggingMode: .silent)) != nil
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

    func inspectSelectedTextForConversationTrigger(
        setStatus: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (String?) -> Void,
        onSelectionUnavailable: @escaping @MainActor () -> Void = {},
        onSelectionAlreadyAttached: @escaping @MainActor () -> Void = {},
        onSelectionReady: @escaping @MainActor () -> Void
    ) {
        do {
            let selectionSnapshot = try selectedTextManager.captureSelectedText(promptForPermission: true, loggingMode: .concise)
            if let latestSelection = snapshot.selectedTextContexts.first,
               latestSelection.isEquivalent(to: selectionSnapshot) {
                setStatus("Selected text is already attached to the context.")
                setError(nil)
                onSelectionAlreadyAttached()
                return
            }

            snapshot.selectedTextContexts.insert(selectionSnapshot, at: 0)
            publishSnapshot()
            onSelectionReady()
            setStatus("Selected text detected in \(selectionSnapshot.appName ?? "the current app") and attached to the context.")
            setError(nil)
        } catch {
            setStatus("No selected text found. Starting screenshot capture instead.")
            setError(error.localizedDescription)
            onSelectionUnavailable()
        }
    }

    private func publishSnapshot() {
        onSnapshotChange(snapshot)
    }
}

private extension SelectedTextManager.SelectionSnapshot {
    func isEquivalent(to other: Self) -> Bool {
        text == other.text
            && appName == other.appName
            && bundleIdentifier == other.bundleIdentifier
            && role == other.role
            && subrole == other.subrole
    }
}