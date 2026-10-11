import NotchGateKit
import SwiftUI

/// Pops up when Claude finishes: read the summary and send the next prompt
/// right from the notch. Claude is not blocked while this is open.
struct CompletionCardView: View {
    let prompt: CompletionPrompt
    let projectName: String
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void
    let onLater: () -> Void

    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Claude is done", subtitle: "What should it do next in \(projectName)?")

            if let summary = prompt.summary, !summary.isEmpty {
                CappedScroll(maxHeight: 170) {
                    MarkdownText(source: summary).padding(14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }

            PromptComposer(
                placeholder: "Message Claude…",
                text: $message,
                onFocus: onFocus,
                onSend: { onDecision(.continueSession(prompt: $0)) }
            )

            HStack {
                Text("Or reply later from the notch. Hover it anytime.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                LinkButton(title: "Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
