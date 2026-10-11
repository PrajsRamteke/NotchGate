import SwiftUI

/// Whether a session can take a prompt from the notch right now.
enum ComposerAvailability: Equatable {
    /// Claude finished and its background hook is waiting: sends instantly.
    case live
    /// Claude is busy: the prompt is delivered the moment it finishes.
    case queue
    /// No hook can reach this session yet (it hasn't finished a turn).
    case unavailable
}

/// Dropdown body of a session row: type a prompt for that project and send it.
struct SessionComposerView: View {
    let projectName: String
    let availability: ComposerAvailability
    let queuedPrompt: String?
    let onFocus: () -> Void
    let onSend: (String) -> Void
    let onCancelQueued: () -> Void
    let onOpenTerminal: () -> Void

    @State private var text = ""

    var body: some View {
        if let queuedPrompt {
            queuedView(queuedPrompt)
        } else if availability == .unavailable {
            unavailableView
        } else {
            VStack(alignment: .leading, spacing: 6) {
                PromptComposer(
                    placeholder: availability == .live ? "Message Claude in \(projectName)…" : "Queue a message for when Claude finishes…",
                    text: $text,
                    autofocus: true,
                    onFocus: onFocus,
                    onSend: onSend
                )
                if availability == .queue {
                    hint("Claude is busy. Your message is sent as soon as it finishes.")
                }
            }
        }
    }

    private func queuedView(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.clay)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Queued, sends when Claude finishes")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(prompt)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            IconButton(systemName: "xmark", help: "Cancel queued message", action: onCancelQueued)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.clay.opacity(0.08)))
    }

    private var unavailableView: some View {
        HStack(spacing: 8) {
            hint("Send this session's first message in its terminal. After that you can prompt it from here.")
            Spacer(minLength: 4)
            LinkButton(title: "Open terminal", action: onOpenTerminal)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
