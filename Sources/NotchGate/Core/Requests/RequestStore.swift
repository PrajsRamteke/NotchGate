import Foundation
import NotchGateKit
import Observation

/// Anything that can deliver the user's decision back to a waiting hook.
protocol DecisionResponder: AnyObject, Sendable {
    func send(_ decision: BridgeDecision)
}

/// FIFO queue of requests awaiting the user, plus the current transient notice.
@MainActor
@Observable
final class RequestStore {
    private struct Pending {
        let request: ClaudeRequest
        let responder: DecisionResponder
    }

    private var queue: [Pending] = []
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]
    private var noticeTask: Task<Void, Never>?

    private(set) var notice: Notice?

    var current: ClaudeRequest? { queue.first?.request }
    var pendingCount: Int { queue.count }
    var hasPending: Bool { !queue.isEmpty }

    enum QueueChange {
        case added(ClaudeRequest)
        case removed(ClaudeRequest, answered: Bool)
    }

    /// Notified on every queue mutation (sound, hotkeys, expansion policy).
    @ObservationIgnored var onQueueChange: ((QueueChange) -> Void)?

    static let noticeDuration: Duration = .seconds(5)

    // MARK: Requests

    func enqueue(_ request: ClaudeRequest, responder: DecisionResponder) {
        queue.append(Pending(request: request, responder: responder))
        scheduleExpiry(for: request)
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
    func clearSession(_ sessionID: String) {
        for pending in queue where pending.request.session.id == sessionID {
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

    /// Releases every waiting hook back to Claude Code's terminal UI.
    func releaseAll() {
        for pending in queue { resolve(pending.request.id, with: .passthrough) }
    }

    private func remove(_ id: UUID) -> Pending? {
        guard let index = queue.firstIndex(where: { $0.request.id == id }) else { return nil }
        expiryTasks.removeValue(forKey: id)?.cancel()
        return queue.remove(at: index)
    }

    private func scheduleExpiry(for request: ClaudeRequest) {
        guard let expiresAt = request.expiresAt else { return }
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        expiryTasks[request.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.resolve(request.id, with: .passthrough)
        }
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
