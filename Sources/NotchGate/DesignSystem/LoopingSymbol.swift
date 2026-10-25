import AppKit
import SwiftUI

/// An SF Symbol playing the repeating variable-color effect, like
/// `.symbolEffect(.variableColor.iterative, options: .repeating)`, but drawn
/// by AppKit. SwiftUI redraws the whole island on every frame of a repeating
/// symbol effect (120 a second on ProMotion), which kept the CPU busy for as
/// long as a session worked. AppKit hands the same effect to Core Animation,
/// so the app does almost no work per frame.
struct LoopingSymbol: View {
    let systemName: String
    var pointSize: CGFloat
    var weight: Font.Weight
    var color: Color
    var isAnimating = true

    var body: some View {
        // The SwiftUI image, hidden, gives the exact size and alignment the
        // symbol had before; AppKit draws it, centered, on top.
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: weight))
            .hidden()
            .overlay {
                SymbolImage(
                    systemName: systemName,
                    pointSize: pointSize,
                    weight: weight.appKit,
                    color: NSColor(color),
                    isAnimating: isAnimating
                )
                .fixedSize()
            }
    }
}

private struct SymbolImage: NSViewRepresentable {
    let systemName: String
    let pointSize: CGFloat
    let weight: NSFont.Weight
    let color: NSColor
    let isAnimating: Bool

    func makeNSView(context: Context) -> SymbolView {
        let view = SymbolView()
        view.imageScaling = .scaleNone
        update(view)
        return view
    }

    func updateNSView(_ view: SymbolView, context: Context) {
        update(view)
    }

    private func update(_ view: SymbolView) {
        let key = "\(systemName)|\(pointSize)|\(weight.rawValue)"
        if view.imageKey != key {
            view.imageKey = key
            view.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        }
        view.contentTintColor = color
        guard view.isAnimating != isAnimating else { return }
        view.isAnimating = isAnimating
        if isAnimating {
            view.addSymbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            view.removeAllSymbolEffects()
        }
    }

    /// Lets clicks fall through to the SwiftUI views around it.
    final class SymbolView: NSImageView {
        var imageKey: String?
        var isAnimating = false

        /// A symbol's glyph overhangs its image size; a whole-point margin keeps
        /// it, and every frame of the effect, inside the view while staying centered.
        private static let margin: CGFloat = 4

        override var intrinsicContentSize: NSSize {
            let size = super.intrinsicContentSize
            return NSSize(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private extension Font.Weight {
    var appKit: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
