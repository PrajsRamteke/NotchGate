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
    /// Sends prompts from the notch into sessions' terminals.
    let prompts: ComposerController
    /// The water-reminder bot that hangs from the notch (an Extra).
    let water: WaterReminder
    /// What's playing on the Mac, and its remote (an Extra).
    let nowPlaying: NowPlayingMonitor
    /// Plan limits for the Usage widget.
    let usage: UsageMonitor
    /// Model, context, cost and branch for the Session widget.
    let session: SessionMonitor
    /// Recent sessions to resume, and new-session launches, for the Resume widget.
    let resume: ResumeMonitor
    /// Cost, tokens and activity from Claude Code's transcripts, for the Insights widget.
    let insights: InsightsMonitor
    /// Snapshots: an Insights bar drawn as if hovered.
    var previewInsightsBar: Int?
    /// Whether a newer NotchGate exists; drives the Update pill in the Activity header.
    let updates: UpdateChecker

    var notch: NotchMetrics = .fallback

    private(set) var isCollapsedByUser = false
    private(set) var isHovering = false
    /// A text field in the island is in use: stay open even if the cursor drifts off.
    private(set) var isComposing = false
    /// The cursor is on the water bot (not the island).
    private(set) var isHoveringWaterBot = false
    /// Images are being dragged somewhere on screen; the notch opens to take them.
    private(set) var isDraggingImages = false

    /// Island frame in window coordinates (top-left origin), reported by SwiftUI.
    @ObservationIgnored var islandFrame: CGRect = .zero {
        didSet { if islandFrame != oldValue { onIslandFrameChange?() } }
    }
    /// The water bot's clickable area in window coordinates; empty while it's tucked away.
    @ObservationIgnored var waterBotFrame: CGRect = .zero {
        didSet { if waterBotFrame != oldValue { onIslandFrameChange?() } }
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

    init(
        store: RequestStore,
        settings: AppSettings,
        activity: ActivityTracker,
        water: WaterReminder? = nil,
        nowPlaying: NowPlayingMonitor? = nil,
        usage: UsageMonitor? = nil,
        session: SessionMonitor? = nil,
        resume: ResumeMonitor? = nil,
        insights: InsightsMonitor? = nil,
        updates: UpdateChecker? = nil
    ) {
        self.store = store
        self.settings = settings
        self.activity = activity
        self.prompts = ComposerController(store: store, activity: activity)
        self.water = water ?? WaterReminder(settings: settings)
        self.nowPlaying = nowPlaying ?? NowPlayingMonitor(settings: settings)
        self.usage = usage ?? UsageMonitor(settings: settings)
        self.session = session ?? SessionMonitor(settings: settings)
        self.resume = resume ?? ResumeMonitor(settings: settings)
        self.insights = insights ?? InsightsMonitor(settings: settings)
        self.updates = updates ?? UpdateChecker(settings: settings)
    }

    /// True when the expanded island is showing live activity rather than a request.
    var isShowingActivity: Bool {
        guard presentation == .expanded else { return false }
        return isAcceptingDrop || isRequestMinimized || (store.current == nil && store.notice == nil)
    }

    /// Dragged images are over the notch: show every session as a drop target,
    /// even over a waiting card, and even if hover activity is turned off.
    var isAcceptingDrop: Bool {
        isDraggingImages && isHovering
    }

    var presentation: IslandPresentation {
        if isAcceptingDrop { return .expanded }
        let engaged = isHovering || isComposing
        if store.current != nil {
            return (isCollapsedByUser && !engaged) ? .peek : .expanded
        }
        if let notice = store.notice {
            // An alert that Claude is blocked opens like a card would.
            return engaged || (notice.blocksClaude && !isCollapsedByUser) ? .expanded : .peek
        }
        if engaged && settings.showActivityOnHover { return .expanded }
        return showsNowPlayingPeek ? .peek : .hidden
    }

    /// Music is playing and Claude needs nothing: the closed notch widens a
    /// little to show the artwork and a live equalizer.
    var showsNowPlayingPeek: Bool {
        settings.nowPlayingInClosedNotch && nowPlaying.isEnabled && nowPlaying.track?.isPlaying == true
            && store.current == nil && store.notice == nil && !isAcceptingDrop
    }

    /// The bot hangs below the notch only while the island is small, so it never
    /// covers a card; while the island is open it waits inside the notch.
    var showsWaterBot: Bool {
        water.state != .away && presentation != .expanded
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
                playFinishedSound()
                return
            }
            playAttentionSound()
        case .removed(_, let answered):
            if answered, settings.playSound { SoundPlayer.play(.resolve, volume: 0.2) }
            if !store.hasPending { isCollapsedByUser = false }
        }
    }

    /// Claude is blocked in the terminal on something not shown as a card.
    func handleAlert(_ notice: Notice) {
        guard !store.hasPending else { return }
        isCollapsedByUser = !settings.autoExpand
        playAttentionSound()
    }

    /// Claude finished, shown as a passing notice rather than the reply box.
    func handleFinishedNotice() {
        playFinishedSound()
    }

    private func playAttentionSound() {
        if settings.playSound { SoundPlayer.play(settings.attentionSound, volume: SoundPlayer.attentionVolume) }
    }

    private func playFinishedSound() {
        if settings.playSound { SoundPlayer.play(settings.finishedSound, volume: SoundPlayer.finishedVolume) }
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

    // MARK: Dropping images

    func setDraggingImages(_ dragging: Bool) {
        if dragging != isDraggingImages { isDraggingImages = dragging }
    }

    /// Attaches dropped images to a session's next prompt and keeps the island
    /// open (and typeable) so the user can add a message.
    func attachImages(_ images: [ImageAttachment], to sessionID: String) {
        prompts.drafts.add(images, to: sessionID)
        beginComposing()
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
        TerminalActivator.activate(claudePID: session.claudePID, cwd: session.cwd)
    }

    func requestKeyFocus() {
        onNeedsKeyFocus?()
    }

    func setHovering(_ hovering: Bool) {
        hoverIntent?.cancel()
        guard hovering != isHovering else { return }

        // An idle notch waits for a deliberate hover (even while it shows what's
        // playing); anything that needs you (peek, notice) responds instantly.
        let isIdle = presentation == .hidden || (presentation == .peek && showsNowPlayingPeek)
        guard hovering, isIdle else { return applyHover(hovering) }
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

    func setHoveringWaterBot(_ hovering: Bool) {
        if hovering != isHoveringWaterBot { isHoveringWaterBot = hovering }
    }

    private func applyHover(_ hovering: Bool) {
        if hovering, store.current == nil, store.notice == nil { activity.prune() }
        isHovering = hovering
        store.holdNotice(hovering)
    }

    func openTerminal(for session: SessionActivity) {
        TerminalActivator.activate(claudePID: session.claudePID, cwd: session.cwd)
    }

    /// Removes a stopped session from the notch without touching Claude: its
    /// leftover cards go back to the terminal and its queued prompt is dropped.
    /// Does nothing while the session is mid-turn.
    func dismissSession(_ sessionID: String) {
        guard activity.dismiss(sessionID) else { return }
        store.cancelQueuedPrompt(for: sessionID)
        store.clearSession(sessionID)
        prompts.drafts.clear(sessionID)
        prompts.texts.clear(sessionID)
    }

    /// Opens a Terminal window running Claude Code, for when no session exists yet.
    func startClaudeCode() {
        ClaudeLauncher.openTerminalWithClaude()
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
