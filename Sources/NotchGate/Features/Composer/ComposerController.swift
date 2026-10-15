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
    /// Images attached to each session's next prompt.
    let drafts = ImageDrafts()
    /// Text typed for each session's next prompt, kept while the island is closed.
    let texts = TextDrafts()

    init(store: RequestStore, activity: ActivityTracker) {
        self.store = store
        self.activity = activity
    }

    func availability(for target: PromptTarget) -> ComposerAvailability {
        if target.isPreview { return .types(into: "your terminal") }
        guard ProcessInspector.isAlive(target.claudePID) else {
            return .unavailable(PromptDeliveryError.sessionEnded.localizedDescription)
        }
        let host = dispatcher.host(for: target.claudePID)
        if host.isSupported { return .types(into: host.displayName) }
        if store.composer(for: target.sessionID) != nil { return .hookOnly(terminal: host.displayName) }
        if activity.sessions[target.sessionID]?.isWorking == true { return .queueOnly(terminal: host.displayName) }
        return .unavailable(PromptDeliveryError.unsupportedTerminal(host.displayName).localizedDescription)
    }

    /// Types the prompt (plus the session's attached images) into its terminal and presses Return.
    /// - Parameter force: send even though Claude seems to be waiting on an answer.
    func send(_ text: String, to target: PromptTarget, force: Bool = false) async -> PromptOutcome {
        let images = drafts.images(for: target.sessionID)
        // Previews never type into a real terminal.
        if target.isPreview {
            drafts.markSent(images, for: target.sessionID)
            return .typed(into: "the preview")
        }
        if !force, let reason = awaitingReason(for: target.sessionID) {
            return .failed(.awaitingAnswer(reason), fallback: nil)
        }
        // Mid-turn, Claude queues the prompt and the hook fires later, so only an
        // idle session gives a clear "it was submitted" signal.
        let session = activity.sessions[target.sessionID]
        let canConfirm = session?.canDismiss == true // idle or finished
        let previousTurn = session?.turnStartedAt
        do {
            let host = try await dispatcher.type(text, images: images.map(\.url), into: target)
            if canConfirm { confirmSubmission(for: target, previousTurn: previousTurn) }
            drafts.markSent(images, for: target.sessionID)
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
        let images = drafts.images(for: target.sessionID)
        guard let payload = try? PromptPayload(text, images: images.map(\.url)) else { return .failed(.emptyPrompt, fallback: nil) }
        drafts.markSent(images, for: target.sessionID)
        switch store.sendPrompt(payload.text, to: target.sessionID) {
        case .sent: return .sentViaHook
        case .queued: return .queued
        }
    }

    // MARK: Private

    /// Presses Return again if Claude Code dropped the first one and the prompt
    /// is still sitting in its input box (no new turn started).
    private func confirmSubmission(for target: PromptTarget, previousTurn: Date?) {
        Task {
            _ = await SubmissionGuard.ensureSubmitted(
                isSubmitted: { activity.sessions[target.sessionID]?.turnStartedAt != previousTurn },
                pressReturn: { try await dispatcher.pressReturn(into: target) }
            )
        }
    }

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
