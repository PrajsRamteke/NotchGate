import SwiftUI

/// One schema-driven input: text/number field, toggle, or choice chips.
struct ElicitationFieldView: View {
    let field: ElicitationField
    @Bindable var form: ElicitationFormModel
    let onFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(field.title)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if field.isRequired {
                    Text("*").foregroundStyle(Theme.Palette.clay)
                }
            }
            if let detail = field.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            input
        }
    }

    @ViewBuilder
    private var input: some View {
        switch field.kind {
        case .boolean:
            Toggle(isOn: flagBinding) { EmptyView() }
                .toggleStyle(.switch)
                .tint(Theme.Palette.clay)
                .labelsHidden()
        case .choice(let options):
            FlowChips(options: options, selection: textBinding)
        case .text, .number, .integer:
            ReplyField(
                placeholder: field.kind == .text ? "Enter \(field.title.lowercased())" : "0",
                text: textBinding,
                lineLimit: 1...3,
                onFocus: onFocus
            )
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: { form.text[field.id] ?? "" }, set: { form.text[field.id] = $0 })
    }

    private var flagBinding: Binding<Bool> {
        Binding(get: { form.flags[field.id] ?? false }, set: { form.flags[field.id] = $0 })
    }
}

/// Wrapping row of selectable capsules for enum fields.
private struct FlowChips: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button(option) { selection = option }
                        .buttonStyle(.plain)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(selected ? Theme.Palette.ivory : Theme.Palette.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.Palette.clay : Theme.Palette.surface))
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                        .animation(.easeOut(duration: 0.15), value: selected)
                }
            }
        }
    }
}
