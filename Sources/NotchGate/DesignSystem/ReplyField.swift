import SwiftUI

/// Multi-line text input styled for the island, with a clay focus ring.
///
/// ⏎ submits; ⇧⏎ inserts a newline.
struct ReplyField: View {
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 1...5
    var autofocus = false
    var onSubmit: (() -> Void)?
    var onFocus: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .tint(Theme.Palette.clay)
            .lineLimit(lineLimit)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Palette.clay.opacity(0.7) : Theme.Palette.hairline,
                        lineWidth: isFocused ? 1 : 0.5
                    )
            )
            .shadow(color: isFocused ? Theme.Palette.clay.opacity(0.25) : .clear, radius: 8)
            .animation(.easeOut(duration: 0.18), value: isFocused)
            .onKeyPress(.return, phases: .down) { press in
                guard !press.modifiers.contains(.shift), let onSubmit else { return .ignored }
                onSubmit()
                return .handled
            }
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus?() }
            }
            .onAppear {
                guard autofocus else { return }
                onFocus?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isFocused = true }
            }
    }
}
