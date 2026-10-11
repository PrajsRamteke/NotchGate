import SwiftUI

/// Expanded form of a transient notice, revealed by hovering the notch.
struct NoticeCardView: View {
    let notice: Notice
    let onOpenTerminal: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: notice.tone.symbol)
                    .foregroundStyle(notice.tone.color)
                Text(notice.session.projectName)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
            }

            CardTitle(title: notice.title)

            if let message = notice.message, !message.isEmpty {
                CappedScroll(maxHeight: 150) {
                    MarkdownText(source: message)
                }
            }

            ActionRow {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.island(.secondary))
                Button("Open terminal", action: onOpenTerminal)
                    .buttonStyle(.island(.primary))
            }
        }
    }
}
