import AppKit
import Foundation

enum OverlayPlacement {
    private enum Layout {
        static let defaultCursorOffset: CGFloat = 0
        static let screenEdgeInset: CGFloat = 12
    }

    /// Offset between the cursor hot spot and the panel edge, in screen points.
    static let contextStackCursorOffset: CGFloat = 0
    static let ttsToastCursorOffset: CGFloat = 20

    static func clampedOrigin(
        for size: NSSize,
        near point: NSPoint,
        cursorOffset: CGFloat = Layout.defaultCursorOffset
    ) -> NSPoint {
        let placementFrame = ScreenLocator.target(containing: point)?.placementFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let rightOriginX = point.x + cursorOffset
        let leftOriginX = point.x - size.width - cursorOffset
        let fitsOnRight = rightOriginX + size.width <= placementFrame.maxX - Layout.screenEdgeInset

        var origin = NSPoint(
            x: fitsOnRight ? rightOriginX : leftOriginX,
            y: point.y - size.height - cursorOffset
        )

        if origin.y < placementFrame.minY {
            origin.y = min(
                point.y + cursorOffset,
                placementFrame.maxY - size.height - Layout.screenEdgeInset
            )
        }

        origin.x = max(origin.x, placementFrame.minX + Layout.screenEdgeInset)
        origin.y = min(
            max(origin.y, placementFrame.minY + Layout.screenEdgeInset),
            placementFrame.maxY - size.height - Layout.screenEdgeInset
        )

        return origin
    }

    static func clampedOriginPreservingUserPosition(proposedOrigin: NSPoint, size: NSSize) -> NSPoint {
        let referencePoint = NSPoint(
            x: proposedOrigin.x + size.width / 2,
            y: proposedOrigin.y + size.height / 2
        )
        let placementFrame = ScreenLocator.target(containing: referencePoint)?.placementFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var origin = proposedOrigin
        origin.x = min(
            max(origin.x, placementFrame.minX + Layout.screenEdgeInset),
            placementFrame.maxX - size.width - Layout.screenEdgeInset
        )
        origin.y = min(
            max(origin.y, placementFrame.minY + Layout.screenEdgeInset),
            placementFrame.maxY - size.height - Layout.screenEdgeInset
        )
        return origin
    }
}
