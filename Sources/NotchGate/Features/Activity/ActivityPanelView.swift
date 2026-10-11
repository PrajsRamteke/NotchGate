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

    private var tracker: ActivityTracker { model.activity }
    private var settings: AppSettings { model.settings }

    var body: some View {
        let sessions = Array(tracker.ordered.prefix(Self.maxVisibleSessions))

        VStack(alignment: .leading, spacing: 12) {
            header(count: tracker.sessions.count)

            NotchWidgetsView(usage: model.usage, session: model.session, sessions: tracker.ordered)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))

            if model.isDraggingImages, !sessions.isEmpty {
                dropHint(sessions: sessions)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if sessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Nothing running", subtitle: "Start Claude Code in any terminal and its progress shows up here.")
                    Button(action: model.startClaudeCode) {
                        Label("Open Claude Code", systemImage: "terminal")
                    }
                    .buttonStyle(.island(.primary))
                    .help("Opens Terminal and starts Claude Code")
                }
                .padding(.bottom, 4)
            } else {
                CappedScroll(maxHeight: 400, scrollTarget: openComposer) {
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
        .animation(Theme.Motion.content, value: settings.usageWidget)
        .animation(Theme.Motion.content, value: settings.usageCardShown)
        .animation(Theme.Motion.content, value: settings.sessionWidget)
        .animation(Theme.Motion.content, value: settings.sessionCardShown)
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
            dropState: dropState(for: session),
            usage: usage(for: session),
            onToggleComposer: { toggleComposer(session.id) },
            onOpen: { model.openTerminal(for: session) }
        ) {
            SessionComposerView(
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
        }
    }
}
