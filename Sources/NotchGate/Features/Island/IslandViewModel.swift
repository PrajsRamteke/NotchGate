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

    var notch: NotchMetrics = .fallback

    private(set) var isCollapsedByUser = false
    private(set) var isHovering = false

    /// Island frame in window coordinates (top-left origin), reported by SwiftUI.
    @ObservationIgnored var islandFrame: CGRect = .zero {
        didSet { if islandFrame != oldValue { onIslandFrameChange?() } }
    }
    /// Lets the window refresh click-through when the island resizes under a still cursor.
    @ObservationIgnored var onIslandFrameChange: (() -> Void)?
    /// Asks the window to become key so text fields can take input.
    @ObservationIgnored var onNeedsKeyFocus: (() -> Void)?

    init(store: RequestStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var presentation: IslandPresentation {
        if store.current != nil {
            return (isCollapsedByUser && !isHovering) ? .peek : .expanded
        }
        if store.notice != nil {
            return isHovering ? .expanded : .peek
        }
        return .hidden
    }

    // MARK: Queue events

    func handle(_ change: RequestStore.QueueChange) {
        switch change {
        case .added:
            if store.pendingCount == 1 { isCollapsedByUser = !settings.autoExpand }
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

    func expand() {
        isCollapsedByUser = false
        onNeedsKeyFocus?()
    }

    func collapse() {
        isCollapsedByUser = true
        isHovering = false
    }

    func toggle() {
        presentation == .expanded ? collapse() : expand()
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
        guard hovering != isHovering else { return }
        isHovering = hovering
        store.holdNotice(hovering)
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
