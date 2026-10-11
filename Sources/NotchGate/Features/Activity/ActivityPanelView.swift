import SwiftUI

/// Revealed by hovering the notch while nothing needs you: a live view of
/// every Claude Code session, with a per-project prompt dropdown.
struct ActivityPanelView: View {
    let model: IslandViewModel

    @State private var openComposer: String?

    init(model: IslandViewModel, openComposer: String? = nil) {
        self.model = model
        _openComposer = State(initialValue: openComposer)
    }

    static let maxVisibleSessions = 4

    private var tracker: ActivityTracker { model.activity }
    private var settings: AppSettings { model.settings }

    var body: some View {
        let sessions = Array(tracker.ordered.prefix(Self.maxVisibleSessions))

        VStack(alignment: .leading, spacing: 12) {
            header(count: tracker.sessions.count)

            if sessions.isEmpty {
                CardTitle(title: "Nothing running", subtitle: "Start Claude Code in any terminal and its progress shows up here.")
                    .padding(.bottom, 4)
            } else {
                CappedScroll(maxHeight: 360, scrollTarget: openComposer) {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            row(for: session)
                                .id(session.id)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(Theme.Motion.content, value: sessions.map(\.id))
            }

            if settings.showQuickSettingsInNotch {
                QuickSettingsView(settings: settings, onSetAutoAllow: model.setAutoAllow)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(Theme.Motion.content, value: settings.showQuickSettingsInNotch)
    }

    private func row(for session: SessionActivity) -> some View {
        let queued = model.store.queuedPrompts[session.id]
        return SessionActivityRow(
            session: session,
            isComposerOpen: openComposer == session.id,
            hasQueuedPrompt: queued != nil,
            onToggleComposer: { toggleComposer(session.id) },
            onOpen: { model.openTerminal(for: session) }
        ) {
            SessionComposerView(
                projectName: session.projectName,
                availability: availability(for: session),
                queuedPrompt: queued,
                onFocus: model.beginComposing,
                onSend: { prompt in
                    let delivery = model.sendPrompt(prompt, to: session.id)
                    if delivery == .sent { openComposer = nil }
                },
                onCancelQueued: { model.store.cancelQueuedPrompt(for: session.id) },
                onOpenTerminal: { model.openTerminal(for: session) }
            )
        }
    }

    private func availability(for session: SessionActivity) -> ComposerAvailability {
        if model.store.composer(for: session.id) != nil { return .live }
        switch session.phase {
        case .thinking, .running, .compacting, .waiting: return .queue
        case .idle, .finished: return .unavailable
        }
    }

    private func toggleComposer(_ id: String) {
        withAnimation(Theme.Motion.content) {
            openComposer = openComposer == id ? nil : id
        }
        if openComposer == nil { model.endComposing() } else { model.beginComposing() }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Label(tracker.workingCount > 0 ? "Live" : "Activity", systemImage: "waveform")
                .font(Theme.Typeface.micro)
                .foregroundStyle(Theme.Palette.clay)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.Palette.clay.opacity(0.12)))
            if settings.autoAllowPermissions {
                Label("Auto-allow", systemImage: "bolt.fill")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if count > 0 {
                Text(count == 1 ? "1 session" : "\(count) sessions")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}
