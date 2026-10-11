import AppKit
import SwiftUI

/// Multi-line text input styled for the island, with a clay focus ring.
///
/// ⏎ submits; ⇧⏎ inserts a newline. With `onPaste`, ⌘V offers the
/// clipboard to the caller first (for images), and pastes text as usual
/// when the caller passes.
struct ReplyField: View {
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 1...5
    var autofocus = false
    var onSubmit: (() -> Void)?
    var onFocus: (() -> Void)?
    /// Return `true` to take the clipboard and skip the normal text paste.
    var onPaste: ((NSPasteboard) -> Bool)?

    @FocusState private var isFocused: Bool
    @State private var pasteMonitor: Any?

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
                focused ? installPasteMonitor() : removePasteMonitor()
            }
            .onDisappear(perform: removePasteMonitor)
            .onAppear {
                guard autofocus else { return }
                onFocus?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isFocused = true }
            }
    }

    // MARK: Paste

    /// SwiftUI's text field only pastes text, so ⌘V is looked at before it gets there.
    private func installPasteMonitor() {
        guard let onPaste, pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPaste = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isPaste, event.window?.firstResponder is NSTextView else { return event }
            let handled = MainActor.assumeIsolated { onPaste(.general) }
            return handled ? nil : event
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }
}
