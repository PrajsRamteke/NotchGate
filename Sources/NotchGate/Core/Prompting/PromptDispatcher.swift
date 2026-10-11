import Foundation

/// Identifies the Claude session a prompt is for.
struct PromptTarget: Equatable, Sendable {
    let sessionID: String
    let claudePID: Int32
    let projectName: String
}

/// Finds each session's terminal (cached per Claude process) and types
/// prompts into it.
@MainActor
final class PromptDispatcher {
    private var hosts: [Int32: TerminalHost] = [:]

    /// The terminal hosting a Claude process. Cheap after the first lookup.
    func host(for claudePID: Int32) -> TerminalHost {
        if let cached = hosts[claudePID] { return cached }
        let host = TerminalHostDetector.detect(claudePID: claudePID)
        hosts[claudePID] = host
        return host
    }

    /// Validates, then types the prompt and presses Return.
    /// - Returns: the terminal it was typed into.
    func type(_ text: String, into target: PromptTarget) async throws(PromptDeliveryError) -> TerminalHost {
        let payload = try PromptPayload(text)
        guard ProcessInspector.isAlive(target.claudePID) else {
            hosts[target.claudePID] = nil
            throw .sessionEnded
        }
        let host = host(for: target.claudePID)
        do {
            try await TerminalTyper.type(payload, into: host)
        } catch {
            Log.app.error("Prompt delivery to \(host.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        Log.app.info("Typed a prompt into \(host.displayName, privacy: .public)")
        return host
    }
}
