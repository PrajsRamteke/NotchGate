import SwiftUI

/// Message field with a round send button: ⏎ sends, ⇧⏎ adds a line.
struct PromptComposer: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    let onFocus: () -> Void
    let onSend: (String) -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ReplyField(
                placeholder: placeholder,
                text: $text,
                lineLimit: 1...6,
                autofocus: autofocus,
                onSubmit: send,
                onFocus: onFocus
            )
            SendButton(isEnabled: !trimmed.isEmpty, action: send)
                .padding(.bottom, 3)
        }
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

/// Circular clay "arrow up" button, the universal send affordance.
struct SendButton: View {
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? Theme.Palette.ivory : Theme.Palette.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isEnabled
                        ? AnyShapeStyle(LinearGradient(
                            colors: [isHovered ? Theme.Palette.clayGlow : Theme.Palette.clay, Theme.Palette.clayDeep],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Theme.Palette.surface))
                )
                .shadow(color: isEnabled ? Theme.Palette.clay.opacity(0.35) : .clear, radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help("Send (⏎)")
        .accessibilityLabel("Send")
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}
