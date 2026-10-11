import SwiftUI

/// Dropdown body of a session row: the conversation so far, then a field to
/// send that project a prompt, or the message already queued for it.
struct SessionComposerView: View {
    let session: SessionActivity
    let controller: ComposerController
    let target: PromptTarget
    let queuedPrompt: String?
    let onFocus: () -> Void
    let onDelivered: () -> Void
    let onCancelQueued: () -> Void
    let onOpenTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConversationHistoryView(
                sessionID: session.id,
                transcriptPath: session.transcriptPath,
                revision: session.updatedAt
            )
            if let queuedPrompt {
                queuedView(queuedPrompt)
            } else {
                NotchComposer(
                    controller: controller,
                    target: target,
                    autofocus: true,
                    onFocus: onFocus,
                    onOpenTerminal: onOpenTerminal,
                    onDelivered: onDelivered
                )
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
}
