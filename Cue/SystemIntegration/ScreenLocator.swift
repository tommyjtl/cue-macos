import AppKit
import CoreGraphics
import Foundation

struct OverlayTarget {
    let screen: NSScreen
    let triggerPoint: NSPoint

    var displayID: CGDirectDisplayID? {
        ScreenLocator.displayID(for: screen)
    }

    var displayFrame: NSRect {
        screen.frame
    }

    var placementFrame: NSRect {
        isFullScreenLike ? displayFrame : screen.visibleFrame
    }

    private var isFullScreenLike: Bool {
        let visibleFrame = screen.visibleFrame
        let tolerance: CGFloat = 1

        return abs(visibleFrame.minX - displayFrame.minX) <= tolerance
            && abs(visibleFrame.minY - displayFrame.minY) <= tolerance
            && abs(visibleFrame.width - displayFrame.width) <= tolerance
            && abs(visibleFrame.height - displayFrame.height) <= tolerance
    }
}

enum ScreenLocator {
    static func target(containing point: NSPoint) -> OverlayTarget? {
        guard let screen = screen(containing: point) else {
            return nil
        }

        return OverlayTarget(screen: screen, triggerPoint: point)
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        if let exactMatch = screens.first(where: { $0.frame.contains(point) }) {
            return exactMatch
        }

        return screens.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.frame) < distanceSquared(from: point, to: rhs.frame)
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let deltaX: CGFloat
        if point.x < rect.minX {
            deltaX = rect.minX - point.x
        } else if point.x > rect.maxX {
            deltaX = point.x - rect.maxX
        } else {
            deltaX = 0
        }

        let deltaY: CGFloat
        if point.y < rect.minY {
            deltaY = rect.minY - point.y
        } else if point.y > rect.maxY {
            deltaY = point.y - rect.maxY
        } else {
            deltaY = 0
        }

        return deltaX * deltaX + deltaY * deltaY
    }
}