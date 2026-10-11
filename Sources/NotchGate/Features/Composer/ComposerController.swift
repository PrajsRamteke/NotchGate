import Foundation

/// What the notch can do with a prompt for a given session right now.
enum ComposerAvailability: Equatable {
    /// Typed straight into the session's terminal, exactly like real typing.
    case types(into: String)
    /// The terminal can't be typed into, but Claude's finished-hook is waiting.
    case hookOnly(terminal: String)
    /// The terminal can't be typed into and Claude is busy: queue for when it stops.
    case queueOnly(terminal: String)
    case unavailable(String)
}

enum HookFallback: Equatable {
    case sendNow, queue
}

enum PromptOutcome: Equatable {
    case typed(into: String)
    case sentViaHook
    case queued
    case failed(PromptDeliveryError, fallback: HookFallback?)
}

/// Sends prompts from the notch to Claude Code sessions: types them into the
/// real terminal when possible, with the background hook as an explicit fallback.
@MainActor
final class ComposerController {
    private let store: RequestStore
    private let activity: ActivityTracker
    private let dispatcher = PromptDispatcher()

    init(store: RequestStore, activity: ActivityTracker) {
        self.store = store
        self.activity = activity
    }

    func availability(for target: PromptTarget) -> ComposerAvailability {
        guard ProcessInspector.isAlive(target.claudePID) else {
            return .unavailable(PromptDeliveryError.sessionEnded.localizedDescription)
        }
        let host = dispatcher.host(for: target.claudePID)
        if host.isSupported { return .types(into: host.displayName) }
        if store.composer(for: target.sessionID) != nil { return .hookOnly(terminal: host.displayName) }
        if activity.sessions[target.sessionID]?.isWorking == true { return .queueOnly(terminal: host.displayName) }
        return .unavailable(PromptDeliveryError.unsupportedTerminal(host.displayName).localizedDescription)
    }

    /// Types the prompt into the session's terminal and presses Return.
    /// - Parameter force: send even though Claude seems to be waiting on an answer.
    func send(_ text: String, to target: PromptTarget, force: Bool = false) async -> PromptOutcome {
        if !force, let reason = awaitingReason(for: target.sessionID) {
            return .failed(.awaitingAnswer(reason), fallback: nil)
        }
        do {
            let host = try await dispatcher.type(text, into: target)
            // Claude got a real prompt; release its finished-hook and any queued message.
            if let composer = store.composer(for: target.sessionID) {
                store.resolve(composer.id, with: .passthrough)
            }
            store.cancelQueuedPrompt(for: target.sessionID)
            return .typed(into: host.displayName)
        } catch {
            return .failed(error, fallback: hookFallback(for: target.sessionID))
        }
    }

    /// The old path: wake Claude through its background Stop hook. Shows in
    /// Claude Code as "Stop hook feedback", so it's only offered as a fallback.
    func sendViaHook(_ text: String, to target: PromptTarget) -> PromptOutcome {
        guard let payload = try? PromptPayload(text) else { return .failed(.emptyPrompt, fallback: nil) }
        switch store.sendPrompt(payload.text, to: target.sessionID) {
        case .sent: return .sentViaHook
        case .queued: return .queued
        }
    }

    // MARK: Private

    private func hookFallback(for sessionID: String) -> HookFallback? {
        if store.composer(for: sessionID) != nil { return .sendNow }
        if activity.sessions[sessionID]?.isWorking == true { return .queue }
        return nil
    }

    /// Typing while Claude shows a dialog would answer that dialog instead.
    private func awaitingReason(for sessionID: String) -> String? {
        if let pending = store.pendingRequest(for: sessionID) { return pending.kind.label }
        if case .waiting(let reason) = activity.sessions[sessionID]?.phase { return reason }
        return nil
    }
}
