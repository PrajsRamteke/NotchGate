import AppKit
import NotchGateKit
import Observation

/// How much of the island is showing.
enum IslandPresentation: Equatable {
    /// Matches the hardware notch exactly — invisible.
    case hidden
    /// Slightly wider than the notch with a status glyph in each "wing".
    case peek
    /// Full interactive card.
    case expanded
}

/// Presentation state for the island and the single entry point for user intents.
@MainActor
@Observable
final class IslandViewModel {
    let store: RequestStore
    let settings: AppSettings
    let activity: ActivityTracker

    var notch: NotchMetrics = .fallback

    private(set) var isCollapsedByUser = false
    private(set) var isHovering = false
    /// A text field in the island is in use: stay open even if the cursor drifts off.
    private(set) var isComposing = false

    /// Island frame in window coordinates (top-left origin), reported by SwiftUI.
    @ObservationIgnored var islandFrame: CGRect = .zero {
        didSet { if islandFrame != oldValue { onIslandFrameChange?() } }
    }
    /// Lets the window refresh click-through when the island resizes under a still cursor.
    @ObservationIgnored var onIslandFrameChange: (() -> Void)?
    /// Asks the window to become key so text fields can take input.
    @ObservationIgnored var onNeedsKeyFocus: (() -> Void)?

    @ObservationIgnored private var hoverIntent: Task<Void, Never>?
    @ObservationIgnored private var parkTimers: [UUID: Task<Void, Never>] = [:]

    /// How long an untouched "Claude is done" card stays before tucking into its row.
    static let composerLinger: Duration = .seconds(12)

    /// Resting time before an idle notch opens the activity panel, so the
    /// cursor sweeping across the top of the screen doesn't trigger it.
    static let hoverIntentDelay: Duration = .milliseconds(180)

    init(store: RequestStore, settings: AppSettings, activity: ActivityTracker) {
        self.store = store
        self.settings = settings
        self.activity = activity
    }

    /// True when the expanded island is showing live activity rather than a request.
    var isShowingActivity: Bool {
        guard presentation == .expanded else { return false }
        return isRequestMinimized || (store.current == nil && store.notice == nil)
    }

    var presentation: IslandPresentation {
        let engaged = isHovering || isComposing
        if store.current != nil {
            return (isCollapsedByUser && !engaged) ? .peek : .expanded
        }
        if store.notice != nil {
            return engaged ? .expanded : .peek
        }
        return engaged && settings.showActivityOnHover ? .expanded : .hidden
    }

    /// The waiting request is minimized but the island is open (hovered), so it
    /// shows live activity; the badge in the status bar brings the card back.
    var isRequestMinimized: Bool {
        store.current != nil && isCollapsedByUser && settings.showActivityOnHover
    }

    // MARK: Queue events

    func handle(_ change: RequestStore.QueueChange) {
        switch change {
        case .added(let request):
            guard !store.isParked(request.id) else { return }
            if store.pendingCount == 1 { isCollapsedByUser = !settings.autoExpand }
            if case .completion = request.kind {
                scheduleParking(request.id)
                if settings.playSound { SoundPlayer.play(.resolve, volume: 0.2) }
                return
            }
            if settings.playSound { SoundPlayer.play(.arrive) }
        case .removed(_, let answered):
            if answered, settings.playSound { SoundPlayer.play(.resolve, volume: 0.2) }
            if !store.hasPending { isCollapsedByUser = false }
        }
    }

    // MARK: Intents

    func respond(_ decision: BridgeDecision) {
        guard let current = store.current else { return }
        store.resolve(current.id, with: decision)
    }

    /// Turns auto-allow on/off and immediately approves cards it now covers.
    func setAutoAllow(_ enabled: Bool) {
        settings.autoAllowPermissions = enabled
        guard enabled else { return }
        let router = RequestRouter(options: settings.routerOptions)
        store.resolvePermissions(where: router.shouldAutoAllow, with: .allow())
    }

    func expand() {
        isCollapsedByUser = false
        onNeedsKeyFocus?()
    }

    /// Minimizes the current card. The island itself stays open while the
    /// cursor is over it; only moving away or clicking outside closes it.
    func collapse() {
        if let current = store.current, case .completion = current.kind {
            store.park(current.id)
        } else {
            isCollapsedByUser = true
        }
        isComposing = false
    }

    // MARK: Composing

    func beginComposing() {
        isComposing = true
        onNeedsKeyFocus?()
    }

    func endComposing() {
        isComposing = false
    }

    /// Sends (or queues) a prompt for a session from the hover panel.
    @discardableResult
    func sendPrompt(_ prompt: String, to sessionID: String) -> RequestStore.PromptDelivery {
        let delivery = store.sendPrompt(prompt, to: sessionID)
        isComposing = false
        return delivery
    }

    /// Tucks an unanswered "Claude is done" card into its session row after a
    /// while, unless the user is reading or typing in it.
    private func scheduleParking(_ id: UUID) {
        parkTimers[id]?.cancel()
        parkTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.composerLinger)
            guard let self, !Task.isCancelled else { return }
            parkTimers[id] = nil
            if isHovering || isComposing { return scheduleParking(id) }
            store.park(id)
        }
    }

    func toggle() {
        let showsCard = presentation == .expanded && store.current != nil && !isRequestMinimized
        showsCard ? collapse() : expand()
    }

    func dismissNotice() {
        store.dismissNotice()
    }

    func openTerminal(for session: SessionInfo) {
        TerminalActivator.activate(claudePID: session.claudePID)
    }

    func requestKeyFocus() {
        onNeedsKeyFocus?()
    }

    func setHovering(_ hovering: Bool) {
        hoverIntent?.cancel()
        guard hovering != isHovering else { return }

        // An idle notch waits for a deliberate hover; anything already
        // visible (peek, notice) responds instantly.
        guard hovering, presentation == .hidden else { return applyHover(hovering) }
        hoverIntent = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverIntentDelay)
            guard !Task.isCancelled else { return }
            self?.applyHover(true)
        }
    }

    /// Session whose prompt dropdown starts open (snapshots, previews).
    @ObservationIgnored var initialComposerSession: String?

    /// Shows the activity panel immediately (snapshots, previews).
    func showActivityNow() {
        applyHover(true)
    }

    private func applyHover(_ hovering: Bool) {
        if hovering, store.current == nil, store.notice == nil { activity.prune() }
        isHovering = hovering
        store.holdNotice(hovering)
    }

    func openTerminal(for session: SessionActivity) {
        TerminalActivator.activate(claudePID: session.claudePID)
    }

    // MARK: Global shortcuts

    func perform(_ action: HotKeyCenter.Action) {
        guard let request = store.current else {
            if action == .reject { dismissNotice() }
            return
        }
        switch action {
        case .toggle:
            toggle()
        case .primary:
            if let decision = Self.quickApproval(for: request.kind) { respond(decision) } else { expand() }
        case .reject:
            respond(Self.quickRejection(for: request.kind))
        }
    }

    /// One-keystroke approval only applies where no extra input is needed.
    static func quickApproval(for kind: RequestKind) -> BridgeDecision? {
        switch kind {
        case .permission: return .allow()
        case .plan(let plan): return .allow(updatedInput: plan.originalInput)
        case .question, .elicitation, .completion: return nil
        }
    }

    static func quickRejection(for kind: RequestKind) -> BridgeDecision {
        switch kind {
        case .permission: return .deny(message: "The user denied this action.")
        case .plan: return .deny(message: "The user rejected the plan. Keep planning and ask what to change.")
        case .elicitation: return .elicitation(action: .decline)
        case .question, .completion: return .passthrough
        }
    }
}
