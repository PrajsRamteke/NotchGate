import SwiftUI

/// Monospaced, selectable code preview with an optional caption and scroll cap.
struct CodeBlock: View {
    let code: String
    var caption: String?
    var maxHeight: CGFloat = 150
    var prompt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(caption)
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            CappedScroll(axes: [.vertical, .horizontal], maxHeight: maxHeight) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let prompt {
                        Text(prompt).foregroundStyle(Theme.Palette.clay)
                    }
                    Text(code)
                        .foregroundStyle(Theme.Palette.textPrimary.opacity(0.92))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .font(Theme.Typeface.code)
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
            )
        }
    }
}
