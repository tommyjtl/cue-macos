import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct CapturedScreenshot: Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let fileURL: URL
    let pixelSize: CGSize

    nonisolated var fileName: String {
        fileURL.lastPathComponent
    }
}

enum CaptureError: LocalizedError {
    case applicationSupportUnavailable
    case captureAlreadyInProgress
    case captureFailed
    case encodingFailed
    case invalidSelection
    case noDisplaysAvailable
    case permissionDenied
    case selectionCancelled

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Cue could not resolve its Application Support folder."
        case .captureAlreadyInProgress:
            return "A screenshot capture is already in progress."
        case .captureFailed:
            return "Cue could not capture the selected screen region."
        case .encodingFailed:
            return "Cue captured the screen but could not save the PNG file."
        case .invalidSelection:
            return "Select a larger area to capture a screenshot."
        case .noDisplaysAvailable:
            return "No active displays are available for capture."
        case .permissionDenied:
            return "Screen Recording permission is required to capture screenshots you explicitly select. If Cue is already enabled in System Settings, quit and reopen the app — unsigned copies can appear as separate entries from an Xcode build."
        case .selectionCancelled:
            return "Screenshot capture was cancelled."
        }
    }
}

struct ScreenCaptureSelection {
    let rect: CGRect
    let displayID: CGDirectDisplayID?
}

final class ScreenCaptureManager {
    private let permissionManager = PermissionManager.shared

    @MainActor
    func capture(selection: ScreenCaptureSelection) async throws -> CapturedScreenshot {
        let normalizedRect = selection.rect.standardized.integral
        guard normalizedRect.width > 2, normalizedRect.height > 2 else {
            throw CaptureError.invalidSelection
        }

        // Do NOT pre-check with CGRequestScreenCaptureAccess — on macOS 14+ that
        // API no longer registers the app in System Settings > Screen Recording.
        // Let the SCK calls below do that; they are what adds Cue to the list.
        do {
            let cgImage = try await captureImage(for: ScreenCaptureSelection(rect: normalizedRect, displayID: selection.displayID))
            return try save(cgImage: cgImage)
        } catch let error as CaptureError {
            throw error
        } catch {
            let hasPermission = await permissionManager.verifyScreenCaptureAccess(force: true)
            if !hasPermission {
                throw CaptureError.permissionDenied
            }
            throw CaptureError.captureFailed
        }
    }

    private func captureImage(for selection: ScreenCaptureSelection) async throws -> CGImage {
        let shareableContent = try await permissionManager.fetchShareableContent(onScreenWindowsOnly: true)
        let displayInfos = shareableContent.displays.map {
            ScreenCaptureGeometry.DisplayInfo(displayID: $0.displayID, frame: $0.frame)
        }

        guard let matchedInfo = ScreenCaptureGeometry.matchDisplay(
            selectionRect: selection.rect,
            preferredDisplayID: selection.displayID,
            displays: displayInfos
        ), let selectedDisplay = shareableContent.displays.first(where: { $0.displayID == matchedInfo.displayID }) else {
            throw CaptureError.captureFailed
        }

        let rectInDisplaySpace = selectionRectInDisplaySpace(selection.rect, displayID: selectedDisplay.displayID)
        let sourceRect = ScreenCaptureGeometry.selectionRectInDisplayLocalSpace(
            rectInDisplaySpace: rectInDisplaySpace,
            displayFrame: selectedDisplay.frame
        )
        .intersection(CGRect(origin: .zero, size: selectedDisplay.frame.size))
        .integral

        guard sourceRect.width > 2, sourceRect.height > 2 else {
            throw CaptureError.invalidSelection
        }

        let filter = SCContentFilter(display: selectedDisplay, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width)
        configuration.height = Int(sourceRect.height)
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func selectionRectInDisplaySpace(_ rect: CGRect, displayID: CGDirectDisplayID) -> CGRect {
        guard let screen = NSScreen.screens.first(where: {
            ScreenLocator.displayID(for: $0) == displayID
        }) else {
            return rect
        }

        return ScreenCaptureGeometry.selectionRectInDisplaySpace(
            selectionRect: rect,
            screenFrame: screen.frame,
            cgDisplayBounds: CGDisplayBounds(displayID)
        )
    }

    private func save(cgImage: CGImage) throws -> CapturedScreenshot {
        let rootURL: URL
        do {
            rootURL = try CueStoragePaths.screenshotsDirectory()
            try CueStoragePaths.ensureDirectoryExists(at: rootURL)
        } catch CueStoragePathsError.applicationSupportUnavailable {
            throw CaptureError.applicationSupportUnavailable
        } catch {
            throw CaptureError.encodingFailed
        }

        let screenshot = CapturedScreenshot(
            id: UUID(),
            createdAt: Date(),
            fileURL: rootURL.appendingPathComponent("\(UUID().uuidString).png"),
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRepresentation.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }

        try pngData.write(to: screenshot.fileURL, options: .atomic)
        return screenshot
    }
}

@MainActor
final class CaptureCoordinator {
    private let selectionController = CaptureSelectionWindowController()
    private let screenCaptureManager = ScreenCaptureManager()

    func beginCapture() async throws -> CapturedScreenshot {
        let selection = try await selectionController.selectRect()
        return try await screenCaptureManager.capture(selection: selection)
    }
}