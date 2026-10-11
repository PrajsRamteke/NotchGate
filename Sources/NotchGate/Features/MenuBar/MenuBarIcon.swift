import AppKit
import SwiftUI

/// Renders the spark glyph as a template image so it adapts to the menu bar.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let renderer = ImageRenderer(content: SparkShape().fill(.black).frame(width: 16, height: 16))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        image.accessibilityDescription = "NotchGate"
        return image
    }()
}
