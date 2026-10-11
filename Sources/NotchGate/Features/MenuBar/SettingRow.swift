import SwiftUI

/// One setting in the menu-bar popover: title and optional detail on the
/// left, an optional accessory, and a clay switch aligned on the right.
struct SettingRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    /// Indents dependent settings under their parent.
    var isIndented = false
    @ViewBuilder var accessory: Accessory

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            Spacer(minLength: 8)
            accessory
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.Palette.clay)
        }
        .padding(.leading, isIndented ? 16 : 0)
        .contentShape(Rectangle())
    }
}

extension SettingRow where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>, isIndented: Bool = false) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.isIndented = isIndented
        self.accessory = EmptyView()
    }
}

/// Small uppercase heading above each group of settings.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

/// Wrapping caption used for explanatory notes under a group.
struct SettingNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
