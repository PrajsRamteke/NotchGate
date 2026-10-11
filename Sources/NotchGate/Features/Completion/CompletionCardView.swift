import SwiftUI

/// Pops up when Claude finishes: read the summary and send the next prompt
/// right from the notch. Claude is not blocked while this is open.
struct CompletionCardView: View {
    let prompt: CompletionPrompt
    let controller: ComposerController
    let target: PromptTarget
    let onFocus: () -> Void
    let onOpenTerminal: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Claude is done", subtitle: "What should it do next in \(target.projectName)?")

            if let summary = prompt.summary, !summary.isEmpty {
                CappedScroll(maxHeight: 170) {
                    MarkdownText(source: summary).padding(14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }

            NotchComposer(
                controller: controller,
                target: target,
                placeholder: "Message Claude…",
                onFocus: onFocus,
                onOpenTerminal: onOpenTerminal
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
