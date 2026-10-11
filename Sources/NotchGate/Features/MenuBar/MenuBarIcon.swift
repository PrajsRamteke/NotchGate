import AppKit
import SwiftUI

/// Renders the spark glyph as a template image so it adapts to the menu bar.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = render(badged: false)
    /// Same glyph with a small dot, shown while an update is waiting.
    static let badgedImage: NSImage = render(badged: true)

    private static func render(badged: Bool) -> NSImage {
        let glyph = ZStack(alignment: .topTrailing) {
            SparkShape().fill(.black).frame(width: 16, height: 16)
            if badged { Circle().fill(.black).frame(width: 5.5, height: 5.5).offset(x: 1, y: -1) }
        }
        let renderer = ImageRenderer(content: glyph.frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = badged ? "NotchGate, update available" : "NotchGate"
        return image
    }
}
