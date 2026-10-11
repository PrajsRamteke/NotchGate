import NotchGateKit
import SwiftUI

/// Review Claude's plan: approve it, or send it back with feedback.
struct PlanCardView: View {
    let plan: PlanPrompt
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void

    @State private var isGivingFeedback = false
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Ready to code?", subtitle: "Claude finished planning. Review before it starts editing.")

            CappedScroll(maxHeight: 230) {
                MarkdownText(source: plan.markdown.isEmpty ? "_The plan is empty._" : plan.markdown)
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
            )

            if isGivingFeedback {
                ReplyField(
                    placeholder: "What should Claude change?",
                    text: $feedback,
                    autofocus: true,
                    onSubmit: keepPlanning,
                    onFocus: onFocus
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ActionRow {
                if let path = plan.filePath {
                    LinkButton(title: "Open plan file") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
            } actions: {
                Button(isGivingFeedback ? "Send feedback" : "Keep planning") {
                    if isGivingFeedback {
                        keepPlanning()
                    } else {
                        withAnimation(Theme.Motion.content) { isGivingFeedback = true }
                    }
                }
                .buttonStyle(.island(.secondary))
                .keyboardShortcut(.cancelAction)

                Button("Approve") { onDecision(.allow(updatedInput: plan.originalInput)) }
                    .buttonStyle(.island(.primary, shortcut: "⏎"))
                    .keyboardShortcut(isGivingFeedback ? nil : .defaultAction)
            }
        }
    }

    private func keepPlanning() {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmed.isEmpty
            ? "The user wants to keep planning. Ask what they'd like to change."
            : "The user reviewed the plan and wants changes before you proceed: \(trimmed)"
        onDecision(.deny(message: message))
    }
}
