import CoreGraphics
import Foundation

/// Pure coordinate transforms for ScreenCaptureKit `sourceRect` configuration.
enum ScreenCaptureGeometry {
    struct DisplayInfo: Equatable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
    }

    static func matchDisplay(
        selectionRect: CGRect,
        preferredDisplayID: CGDirectDisplayID?,
        displays: [DisplayInfo]
    ) -> DisplayInfo? {
        if let preferredDisplayID,
           let match = displays.first(where: { $0.displayID == preferredDisplayID }) {
            return match
        }

        let probePoint = CGPoint(x: selectionRect.midX, y: selectionRect.midY)
        if let match = displays.first(where: { $0.frame.contains(probePoint) }) {
            return match
        }

        return displays.first(where: { $0.frame.intersects(selectionRect) })
    }

    /// Maps an AppKit selection rect into Core Graphics global display space.
    static func selectionRectInDisplaySpace(
        selectionRect: CGRect,
        screenFrame: CGRect,
        cgDisplayBounds: CGRect
    ) -> CGRect {
        selectionRect.offsetBy(
            dx: cgDisplayBounds.minX - screenFrame.minX,
            dy: cgDisplayBounds.minY - screenFrame.minY
        )
    }

    /// Maps a global display-space rect into ScreenCaptureKit bottom-left `sourceRect` space.
    static func selectionRectInDisplayLocalSpace(
        rectInDisplaySpace: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        let localRect = rectInDisplaySpace.offsetBy(
            dx: -displayFrame.minX,
            dy: -displayFrame.minY
        )

        return CGRect(
            x: localRect.minX,
            y: displayFrame.height - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
    }
}
