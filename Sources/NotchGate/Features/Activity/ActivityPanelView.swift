import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Revealed by hovering the notch while nothing needs you: a live view of
/// every Claude Code session, with a per-project prompt dropdown.
///
/// Dragging images onto the notch opens it too: each session row becomes a
/// drop target, so the images go to whichever project they're dropped on.
struct ActivityPanelView: View {
    let model: IslandViewModel

    @State private var openComposer: String?
    /// Session row the dragged images are over.
    @State private var dropTarget: String?
    /// Dragged images are over the panel but not a row (one session: still its drop).
    @State private var isPanelTargeted = false
    /// Session rows showing their model, context, cost and branch.
    @State private var openUsage: Set<String> = []

    static let dropTypes: [UTType] = [.fileURL, .image]

    init(model: IslandViewModel, openComposer: String? = nil) {
        self.model = model
        _openComposer = State(initialValue: openComposer)
    }

    static let maxVisibleSessions = 4

    /// Height of the window under the island's top strip and this panel's header,
    /// leaving room for the island's padding and shadow.
    private var scrollHeight: CGFloat {
        let chrome = model.notch.notchSize.height + 10 + Theme.Metrics.contentPadding + Self.headerHeight + 12 + Self.bottomMargin
        return max(200, Theme.Metrics.canvasSize.height - chrome)
    }

    private static let headerHeight: CGFloat = 26
    private static let bottomMargin: CGFloat = 28

    private var tracker: ActivityTracker { model.activity }
    private var settings: AppSettings { model.settings }

    var body: some View {
        let sessions = Array(tracker.ordered.prefix(Self.maxVisibleSessions))

        VStack(alignment: .leading, spacing: 12) {
            header(count: tracker.sessions.count)

            // Widgets, sessions and settings scroll together under the header,
            // so a tall panel never runs past the bottom of its window.
            CappedScroll(maxHeight: scrollHeight, scrollTarget: openComposer, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if model.nowPlaying.isEnabled, settings.nowPlayingCardShown {
                        NowPlayingCardView(monitor: model.nowPlaying)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }

                    NotchWidgetsView(
                        usage: model.usage,
                        session: model.session,
                        resume: model.resume,
                        sessions: tracker.ordered,
                        dismissedIDs: Set(tracker.dismissed.keys)
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

                    if model.isDraggingImages, !sessions.isEmpty {
                        dropHint(sessions: sessions)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            CardTitle(title: "Nothing running", subtitle: "Start Claude Code in any terminal and its progress shows up here.")
                            // The Resume card has its own "New session" button.
                            if !(model.resume.isEnabled && settings.resumeCardShown) {
                                Button(action: model.startClaudeCode) {
                                    Label("Open Claude Code", systemImage: "terminal")
                                }
                                .buttonStyle(.island(.primary))
                                .help("Opens Terminal and starts Claude Code")
                            }
                        }
                        .padding(.bottom, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sessions) { session in
                                row(for: session)
                                    .id(session.id)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(Theme.Motion.content, value: sessions.map(\.id))
                    }

                    if settings.showQuickSettingsInNotch {
                        QuickSettingsView(settings: settings, onSetAutoAllow: model.setAutoAllow)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
            }
        }
        .animation(Theme.Motion.content, value: settings.showQuickSettingsInNotch)
        .animation(Theme.Motion.content, value: settings.nowPlaying)
        .animation(Theme.Motion.content, value: settings.nowPlayingCardShown)
        .animation(Theme.Motion.content, value: settings.usageWidget)
        .animation(Theme.Motion.content, value: settings.usageCardShown)
        .animation(Theme.Motion.content, value: settings.sessionWidget)
        .animation(Theme.Motion.content, value: settings.sessionCardShown)
        .animation(Theme.Motion.content, value: settings.toolsWidget)
        .animation(Theme.Motion.content, value: settings.toolsCardShown)
        .animation(Theme.Motion.content, value: settings.resumeWidget)
        .animation(Theme.Motion.content, value: settings.resumeCardShown)
        .animation(Theme.Motion.content, value: model.isDraggingImages)
        // With a single session, dropping anywhere on the panel is unambiguous.
        .onDrop(of: Self.dropTypes, isTargeted: $isPanelTargeted) { _ in
            guard sessions.count == 1, let only = sessions.first else { return false }
            return drop(on: only)
        }
    }

    private func row(for session: SessionActivity) -> some View {
        let queued = model.store.queuedPrompts[session.id]
        return SessionActivityRow(
            session: session,
            isComposerOpen: openComposer == session.id,
            hasQueuedPrompt: queued != nil,
            hasDraft: model.prompts.texts.hasDraft(for: session.id) || !model.prompts.drafts.images(for: session.id).isEmpty,
            dropState: dropState(for: session),
            usage: usage(for: session),
            onToggleComposer: { toggleComposer(session.id) },
            onOpen: { model.openTerminal(for: session) },
            onDismiss: { dismiss(session.id) }
        ) {
            SessionComposerView(
                session: session,
                controller: model.prompts,
                target: PromptTarget(sessionID: session.id, claudePID: session.claudePID, projectName: session.projectName),
                queuedPrompt: queued,
                onFocus: model.beginComposing,
                onDelivered: { model.endComposing() },
                onCancelQueued: { model.store.cancelQueuedPrompt(for: session.id) },
                onOpenTerminal: { model.openTerminal(for: session) }
            )
        }
        .onDrop(of: Self.dropTypes, isTargeted: dropBinding(for: session.id)) { _ in drop(on: session) }
    }

    // MARK: Dropping images

    private func dropState(for session: SessionActivity) -> SessionDropState {
        guard model.isDraggingImages else { return .none }
        let single = tracker.sessions.count == 1
        return dropTarget == session.id || (single && isPanelTargeted) ? .targeted : .available
    }

    private func dropBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { dropTarget == id },
            set: { targeted in
                if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
            }
        )
    }

    /// Saves the dragged images for this session and opens its prompt field.
    private func drop(on session: SessionActivity) -> Bool {
        dropTarget = nil
        guard model.isDraggingImages else { return false }
        let images = ImageIntake.attachments(
            from: NSPasteboard(name: .drag),
            limit: model.prompts.drafts.remaining(for: session.id)
        )
        guard !images.isEmpty else { return false }
        model.attachImages(images, to: session.id)
        withAnimation(Theme.Motion.content) { openComposer = session.id }
        return true
    }

    private func dropHint(sessions: [SessionActivity]) -> some View {
        let message = sessions.count == 1
            ? "Drop to attach to \(sessions[0].projectName)"
            : "Drop on a project to attach the image"
        return Label(message, systemImage: "photo.on.rectangle.angled")
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.clayGlow)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.clay.opacity(0.1)))
    }

    /// The row's Session widget button, while that widget is on.
    private func usage(for session: SessionActivity) -> SessionRowUsage? {
        guard model.session.isEnabled else { return nil }
        let id = session.id
        return SessionRowUsage(
            snapshot: model.session.snapshot(for: id),
            isOpen: openUsage.contains(id),
            toggle: { if openUsage.remove(id) == nil { openUsage.insert(id) } }
        )
    }

    private func dismiss(_ id: String) {
        withAnimation(Theme.Motion.content) {
            if openComposer == id {
                openComposer = nil
                model.endComposing()
            }
            openUsage.remove(id)
            model.dismissSession(id)
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
            if model.updates.isUpdateAvailable {
                NotchUpdateButton(updates: model.updates)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            Spacer()
            if count > 0 {
                Text(count == 1 ? "1 session" : "\(count) sessions")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            if settings.nowPlaying {
                CardToggleButton(
                    systemName: "music.note",
                    name: "now playing",
                    isOn: settings.nowPlayingCardShown
                ) { settings.nowPlayingCardShown.toggle() }
            }
            if settings.usageWidget {
                CardToggleButton(
                    systemName: "gauge.with.dots.needle.50percent",
                    name: "usage",
                    isOn: settings.usageCardShown
                ) { settings.usageCardShown.toggle() }
            }
            if settings.sessionWidget {
                CardToggleButton(
                    systemName: "cpu",
                    name: "sessions",
                    isOn: settings.sessionCardShown
                ) { settings.sessionCardShown.toggle() }
            }
            if settings.toolsWidget {
                CardToggleButton(
                    systemName: "hammer",
                    name: "tool activity",
                    isOn: settings.toolsCardShown
                ) { settings.toolsCardShown.toggle() }
            }
            if settings.resumeWidget {
                CardToggleButton(
                    systemName: "clock.arrow.circlepath",
                    name: "resume",
                    isOn: settings.resumeCardShown
                ) { settings.resumeCardShown.toggle() }
            }
        }
    }
}
