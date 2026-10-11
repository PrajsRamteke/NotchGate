import SwiftUI

/// Unified-style diff of an edit: removed lines tinted red, added tinted green.
struct DiffPreviewView: View {
    let removed: String
    let added: String
    var maxLinesPerSide = 40

    var body: some View {
        CappedScroll(axes: [.vertical, .horizontal], maxHeight: 180) {
            VStack(alignment: .leading, spacing: 0) {
                lines(removed, marker: "−", tint: Theme.Palette.codeRemoved, accent: Theme.Palette.danger)
                lines(added, marker: "+", tint: Theme.Palette.codeAdded, accent: Theme.Palette.success)
            }
            .padding(.vertical, 8)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func lines(_ text: String, marker: String, tint: Color, accent: Color) -> some View {
        let all = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let visible = all.prefix(maxLinesPerSide)
        ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(accent)
                Text(line.isEmpty ? " " : line)
                    .foregroundStyle(Theme.Palette.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(Theme.Typeface.code)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
        }
        if all.count > maxLinesPerSide {
            Text("… \(all.count - maxLinesPerSide) more lines")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }
}
