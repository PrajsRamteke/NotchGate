import Foundation
import NotchGateKit
import Observation

/// Anything that can deliver the user's decision back to a waiting hook.
protocol DecisionResponder: AnyObject, Sendable {
    func send(_ decision: BridgeDecision)
}

/// FIFO queue of requests awaiting the user, plus the current transient notice.
///
/// "Composers" (`.completion`) are special: they never block Claude, so once
/// parked they leave the island free and live on in the hover panel's rows.
@MainActor
@Observable
final class RequestStore {
    private struct Pending {
        let request: ClaudeRequest
        let responder: DecisionResponder
    }

    private var queue: [Pending] = []
    private var noticeTask: Task<Void, Never>?
    private var parked: Set<UUID> = []

    private(set) var notice: Notice?
    /// Prompts typed for a busy session, delivered the moment it finishes.
    private(set) var queuedPrompts: [String: String] = [:]

    private var visible: [Pending] { queue.filter { !parked.contains($0.request.id) } }

    var current: ClaudeRequest? { visible.first?.request }
    var pendingCount: Int { visible.count }
    var hasPending: Bool { !visible.isEmpty }

    enum QueueChange {
        case added(ClaudeRequest)
        case removed(ClaudeRequest, answered: Bool)
    }

    /// Notified on every queue mutation (sound, hotkeys, expansion policy).
    @ObservationIgnored var onQueueChange: ((QueueChange) -> Void)?

    static let noticeDuration: Duration = .seconds(5)

    // MARK: Requests

    func enqueue(_ request: ClaudeRequest, responder: DecisionResponder, parked isParked: Bool = false) {
        // One composer per session: a newer "Claude is done" replaces the old one.
        if case .completion = request.kind {
            for pending in queue where pending.request.session.id == request.session.id {
                if case .completion = pending.request.kind { resolve(pending.request.id, with: .passthrough) }
            }
        }
        queue.append(Pending(request: request, responder: responder))
        if isParked { parked.insert(request.id) }
        onQueueChange?(.added(request))
    }

    /// Sends the decision to the hook and removes the request.
    func resolve(_ id: UUID, with decision: BridgeDecision) {
        guard let pending = remove(id) else { return }
        pending.responder.send(decision)
        onQueueChange?(.removed(pending.request, answered: decision != .passthrough))
    }

    /// Drops a request whose hook already went away (answered in the terminal,
    /// timed out, or Claude was interrupted).
    func cancel(_ id: UUID) {
        guard let pending = remove(id) else { return }
        onQueueChange?(.removed(pending.request, answered: false))
    }

    /// The user returned to the terminal for `sessionID`; release its cards.
    /// `keepingComposer` spares the "Claude is done" card (used on Stop).
    func clearSession(_ sessionID: String, keepingComposer: Bool = false) {
        for pending in queue where pending.request.session.id == sessionID {
            if keepingComposer, case .completion = pending.request.kind { continue }
            resolve(pending.request.id, with: .passthrough)
        }
        if notice?.session.id == sessionID { dismissNotice() }
    }

    /// A tool finished running, so it was approved somewhere else (terminal,
    /// auto mode, an allow rule). Drop any card still asking about it.
    func dismissCompletedTool(sessionID: String, toolName: String, input: JSONValue) {
        for pending in queue where pending.request.session.id == sessionID {
            guard case .permission(let permission) = pending.request.kind,
                  permission.toolName == toolName, permission.input == input else { continue }
            resolve(pending.request.id, with: .passthrough)
        }
    }

    /// Resolves every waiting permission card that `predicate` accepts.
    func resolvePermissions(where predicate: (ToolPermission) -> Bool, with decision: BridgeDecision) {
        for pending in queue {
            guard case .permission(let permission) = pending.request.kind, predicate(permission) else { continue }
            resolve(pending.request.id, with: decision)
        }
    }

    /// Releases every waiting hook back to Claude Code's terminal UI.
    func releaseAll() {
        for pending in queue { resolve(pending.request.id, with: .passthrough) }
    }

    private func remove(_ id: UUID) -> Pending? {
        guard let index = queue.firstIndex(where: { $0.request.id == id }) else { return nil }
        parked.remove(id)
        return queue.remove(at: index)
    }

    // MARK: Composers (send Claude a prompt from the notch)

    func isParked(_ id: UUID) -> Bool { parked.contains(id) }

    /// A request (other than a composer) that blocks this session on the user.
    func pendingRequest(for sessionID: String) -> ClaudeRequest? {
        queue.first { pending in
            guard pending.request.session.id == sessionID else { return false }
            if case .completion = pending.request.kind { return false }
            return true
        }?.request
    }

    /// Tucks a composer away: the island frees up, its session row keeps it.
    func park(_ id: UUID) {
        guard queue.contains(where: { $0.request.id == id }) else { return }
        parked.insert(id)
    }

    /// The live composer for a session, if its background Stop hook is waiting.
    func composer(for sessionID: String) -> ClaudeRequest? {
        queue.first { pending in
            guard pending.request.session.id == sessionID, case .completion = pending.request.kind else { return false }
            return true
        }?.request
    }

    enum PromptDelivery: Equatable { case sent, queued }

    /// Sends now if the session is waiting for a prompt, otherwise queues it
    /// for the session's next stop.
    @discardableResult
    func sendPrompt(_ prompt: String, to sessionID: String) -> PromptDelivery {
        if let composer = composer(for: sessionID) {
            resolve(composer.id, with: .continueSession(prompt: prompt))
            return .sent
        }
        queuedPrompts[sessionID] = prompt
        return .queued
    }

    func cancelQueuedPrompt(for sessionID: String) {
        queuedPrompts[sessionID] = nil
    }

    /// Hands over (and forgets) the prompt queued for a session.
    func takeQueuedPrompt(for sessionID: String) -> String? {
        queuedPrompts.removeValue(forKey: sessionID)
    }

    // MARK: Notices

    func post(_ notice: Notice) {
        self.notice = notice
        scheduleNoticeDismissal()
    }

    /// Pauses auto-dismissal while the user is reading (hovering) the notice.
    func holdNotice(_ held: Bool) {
        guard notice != nil else { return }
        if held { noticeTask?.cancel() } else { scheduleNoticeDismissal() }
    }

    private func scheduleNoticeDismissal() {
        guard let id = notice?.id else { return }
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled, self?.notice?.id == id else { return }
            self?.notice = nil
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }
}
