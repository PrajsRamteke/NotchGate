import SwiftUI

/// A section's settings on one rounded card, rows split by hairlines
/// (`GroupDivider`), like System Settings.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

/// Hairline between rows of a `SettingsGroup`.
struct GroupDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

/// A setting's name with its ⓘ: what it does lives in the hover bubble, not
/// under the title.
struct SettingLabel: View {
    let title: String
    var info: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
            if let info {
                InfoButton(text: info, title: title)
            }
        }
    }
}

/// One switch: title and ⓘ on the left, an optional accessory, and a clay
/// switch on the right.
struct SettingRow<Accessory: View>: View {
    let title: String
    var info: String?
    @Binding var isOn: Bool
    /// Indents dependent settings under their parent.
    var isIndented = false
    /// Greys the row and locks the switch, but keeps its ⓘ hoverable so it
    /// can still explain itself.
    var isDisabled = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            SettingLabel(title: title, info: info)
                .foregroundStyle(isDisabled ? .tertiary : .primary)
            Spacer(minLength: 8)
            accessory
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.Palette.clay)
                .disabled(isDisabled)
        }
        .settingRowPadding(isIndented: isIndented)
    }
}

extension SettingRow where Accessory == EmptyView {
    init(_ title: String, info: String? = nil, isOn: Binding<Bool>, isIndented: Bool = false, isDisabled: Bool = false) {
        self.title = title
        self.info = info
        self._isOn = isOn
        self.isIndented = isIndented
        self.isDisabled = isDisabled
        self.accessory = EmptyView()
    }
}

/// A live one-liner under a row: what the setting is doing right now, or
/// what went wrong.
struct SettingStatus: View {
    enum Tone { case normal, warning, error }

    let text: String
    var tone: Tone = .normal
    var isIndented = false

    init(_ text: String, tone: Tone = .normal, isIndented: Bool = false) {
        self.text = text
        self.tone = tone
        self.isIndented = isIndented
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.leading, isIndented ? 14 : 0)
        .padding(.top, -3)
        .padding(.bottom, 7)
    }

    private var symbol: String? {
        switch tone {
        case .normal: return nil
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: AnyShapeStyle {
        switch tone {
        case .normal: return AnyShapeStyle(.secondary)
        case .warning: return AnyShapeStyle(Theme.Palette.warning)
        case .error: return AnyShapeStyle(Theme.Palette.danger)
        }
    }
}

extension View {
    /// The vertical rhythm every row in a `SettingsGroup` shares.
    func settingRowPadding(isIndented: Bool = false) -> some View {
        self
            .frame(minHeight: 22)
            .padding(.vertical, 6)
            .padding(.leading, isIndented ? 14 : 0)
            .contentShape(Rectangle())
    }
}

/// Wrapping caption for a longer note (e.g. the update banner).
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
