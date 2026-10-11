import SwiftUI

/// A tiny keycap showing the shortcut for an action (e.g. "⏎", "⎋").
struct KeyHint: View {
    private let symbol: String
    private let tint: Color?

    init(_ symbol: String, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(tint ?? Theme.Palette.textTertiary)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .accessibilityHidden(true)
    }
}
