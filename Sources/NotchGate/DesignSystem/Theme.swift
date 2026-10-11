import SwiftUI

/// Single source of truth for NotchGate's visual language.
///
/// The island is always dark: it grows out of the hardware notch, so pure
/// black lets it read as a physical extension of the display. Claude's warm
/// clay accent and ivory type carry the brand on top of that canvas.
enum Theme {
    enum Palette {
        static let island = Color.black
        static let clay = Color(hex: 0xD97757)
        static let clayDeep = Color(hex: 0xC15F3C)
        static let clayGlow = Color(hex: 0xE8916F)
        static let ivory = Color(hex: 0xF5F3EC)

        static let textPrimary = ivory
        static let textSecondary = ivory.opacity(0.64)
        static let textTertiary = ivory.opacity(0.40)

        static let surface = Color.white.opacity(0.055)
        static let surfaceRaised = Color.white.opacity(0.085)
        static let hairline = Color.white.opacity(0.08)

        static let danger = Color(hex: 0xE5675B)
        static let warning = Color(hex: 0xE3A857)
        static let success = Color(hex: 0x6CC49A)
        static let codeAdded = Color(hex: 0x6CC49A).opacity(0.16)
        static let codeRemoved = Color(hex: 0xE5675B).opacity(0.16)
    }

    enum Typeface {
        static let title = Font.system(size: 16, weight: .semibold, design: .serif)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
        static let micro = Font.system(size: 10, weight: .semibold).smallCaps()
        static let code = Font.system(size: 11.5, weight: .regular, design: .monospaced)
        static let button = Font.system(size: 12.5, weight: .semibold)
    }

    enum Metrics {
        /// Transparent canvas the panel reserves at the top of the screen.
        static let canvasSize = CGSize(width: 680, height: 740)
        static let expandedWidth: CGFloat = 500
        static let expandedMaxContentHeight: CGFloat = 400
        static let peekWingWidth: CGFloat = 92
        static let contentPadding: CGFloat = 18
        static let expandedCornerRadius: CGFloat = 30
        static let peekCornerRadius: CGFloat = 14
        static let notchTopRadius: CGFloat = 8
        static let buttonHeight: CGFloat = 32
    }

    enum Motion {
        /// The signature "grow out of the notch" spring.
        static let expand = Animation.spring(response: 0.48, dampingFraction: 0.78, blendDuration: 0.1)
        static let collapse = Animation.spring(response: 0.38, dampingFraction: 0.92)
        static let content = Animation.easeOut(duration: 0.22)
        static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
    }
}

extension Color {
    /// Creates a color from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
