import SwiftUI

/// Revealed by hovering the notch while nothing needs you: a live view of
/// every Claude Code session and what it's doing.
struct ActivityPanelView: View {
    let tracker: ActivityTracker
    let onOpen: (SessionActivity) -> Void

    static let maxVisibleSessions = 4

    var body: some View {
        let sessions = Array(tracker.ordered.prefix(Self.maxVisibleSessions))

        VStack(alignment: .leading, spacing: 12) {
            header(count: tracker.sessions.count)

            if sessions.isEmpty {
                emptyState
            } else {
                CappedScroll(maxHeight: 380) {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            SessionActivityRow(session: session) { onOpen(session) }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(Theme.Motion.content, value: sessions.map(\.id))
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Label(tracker.workingCount > 0 ? "Live" : "Activity", systemImage: "waveform")
                .font(Theme.Typeface.micro)
                .foregroundStyle(Theme.Palette.clay)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.Palette.clay.opacity(0.12)))
            Spacer()
            if count > 0 {
                Text(count == 1 ? "1 session" : "\(count) sessions")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(title: "Nothing running", subtitle: "Start Claude Code in any terminal and its progress shows up here.")
        }
        .padding(.bottom, 4)
    }
}
