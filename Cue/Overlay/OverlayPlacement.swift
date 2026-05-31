import AppKit
import Foundation

enum OverlayPlacement {
    private enum Layout {
        static let cursorOffset: CGFloat = 0
        static let screenEdgeInset: CGFloat = 12
    }

    static func clampedOrigin(for size: NSSize, near point: NSPoint) -> NSPoint {
        let placementFrame = ScreenLocator.target(containing: point)?.placementFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let rightOriginX = point.x + Layout.cursorOffset
        let leftOriginX = point.x - size.width - Layout.cursorOffset
        let fitsOnRight = rightOriginX + size.width <= placementFrame.maxX - Layout.screenEdgeInset

        var origin = NSPoint(
            x: fitsOnRight ? rightOriginX : leftOriginX,
            y: point.y - size.height - Layout.cursorOffset
        )

        if origin.y < placementFrame.minY {
            origin.y = min(
                point.y + Layout.cursorOffset,
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
}
