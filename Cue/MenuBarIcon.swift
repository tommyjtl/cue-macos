import AppKit

enum MenuBarIcon {
    /// Menu bar glyph size in points. macOS ignores SwiftUI `.frame` on `MenuBarExtra` labels;
    /// sizing must be baked into the `NSImage` point size.
    static let pointSize: CGFloat = 19

    static let templateImage: NSImage = makeTemplateImage(pointSize: pointSize)

    static func makeTemplateImage(pointSize: CGFloat) -> NSImage {
        guard let source = NSImage(named: "MenuBarIcon") else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }

        source.isTemplate = true
        let size = NSSize(width: pointSize, height: pointSize)

        let image = NSImage(size: size, flipped: false) { bounds in
            source.draw(in: bounds)
            return true
        }
        image.isTemplate = true
        return image
    }
}
