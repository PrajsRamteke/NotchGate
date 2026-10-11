import NotchGateKit
import SwiftUI

/// Shown when Claude stops and "Reply from the notch" is enabled: read the
/// summary, then either let Claude rest or send a follow-up to keep going.
struct CompletionCardView: View {
    let prompt: CompletionPrompt
    let receivedAt: Date
    let expiresAt: Date?
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void

    @State private var reply = ""

    private var trimmedReply: String { reply.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                CardTitle(title: "Claude is done", subtitle: "Reply to keep going, or let it rest.")
                if let expiresAt {
                    CountdownRing(start: receivedAt, deadline: expiresAt)
                        .padding(.top, 3)
                }
            }

            if let summary = prompt.summary, !summary.isEmpty {
                CappedScroll(maxHeight: 170) {
                    MarkdownText(source: summary).padding(14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }

            ReplyField(
                placeholder: "Reply to Claude…",
                text: $reply,
                onSubmit: send,
                onFocus: onFocus
            )

            ActionRow {
                Button("Done") { onDecision(.passthrough) }
                    .buttonStyle(.island(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: send)
                    .buttonStyle(.island(.primary, shortcut: "⏎"))
                    .disabled(trimmedReply.isEmpty)
            }
        }
    }

    private func send() {
        guard !trimmedReply.isEmpty else { return }
        onDecision(.continueSession(prompt: trimmedReply))
    }
}
