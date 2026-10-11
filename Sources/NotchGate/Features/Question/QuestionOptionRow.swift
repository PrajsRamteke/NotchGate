import SwiftUI

/// A selectable answer: radio dot for single-select, checkbox for multi-select.
struct QuestionOptionRow: View {
    let label: String
    let detail: String?
    let isSelected: Bool
    let isMultiSelect: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                indicator.padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.Typeface.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.Palette.clay.opacity(0.13) : (isHovered ? Theme.Palette.surfaceRaised : Theme.Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.clay.opacity(0.55) : Theme.Palette.hairline, lineWidth: isSelected ? 1 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var indicator: some View {
        let stroke = isSelected ? Theme.Palette.clay : Theme.Palette.textTertiary
        Group {
            if isMultiSelect {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isSelected ? Theme.Palette.clay : .clear)
                    )
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundStyle(Theme.Palette.ivory)
                        }
                    }
            } else {
                Circle()
                    .strokeBorder(stroke, lineWidth: 1.2)
                    .overlay {
                        if isSelected { Circle().fill(Theme.Palette.clay).frame(width: 7, height: 7) }
                    }
            }
        }
        .frame(width: 15, height: 15)
    }
}
