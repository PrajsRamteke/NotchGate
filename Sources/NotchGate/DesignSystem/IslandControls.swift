import SwiftUI

/// Compact switch row styled for the dark island.
struct IslandToggleRow: View {
    let title: String
    var caption: String?
    var symbol: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.Palette.clay : Theme.Palette.textTertiary)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.Palette.clay)
                .labelsHidden()
        }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Capsule segmented control for small enumerations (e.g. question mode).
struct IslandSegmented<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selected ? Theme.Palette.ivory : Theme.Palette.textSecondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Theme.Palette.clay)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.Palette.surface))
        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}
