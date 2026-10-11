import Foundation

/// Hook → App. One message per hook invocation.
public struct BridgeRequest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var id: UUID
    public var event: HookEvent
    public var expectsReply: Bool
    /// The raw JSON Claude Code passed to the hook on stdin.
    public var payload: JSONValue
    public var origin: ProcessOrigin

    public init(
        id: UUID = UUID(),
        event: HookEvent,
        payload: JSONValue,
        origin: ProcessOrigin
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.event = event
        self.expectsReply = event.expectsReply
        self.payload = payload
        self.origin = origin
    }
}

/// Where the request came from, so the app can jump back to the right terminal.
public struct ProcessOrigin: Codable, Sendable, Equatable {
    /// PID of the Claude Code process (the hook's parent).
    public var claudePID: Int32

    public init(claudePID: Int32) {
        self.claudePID = claudePID
    }
}

/// App → Hook. Sent once for events where `expectsReply` is true.
public struct BridgeReply: Codable, Sendable, Equatable {
    public var id: UUID
    public var decision: BridgeDecision

    public init(id: UUID, decision: BridgeDecision) {
        self.id = id
        self.decision = decision
    }
}

/// What the user decided, expressed independently of Claude Code's output format.
/// `HookOutput` translates it into the exact JSON each hook event expects.
public enum BridgeDecision: Codable, Sendable, Equatable {
    /// Do nothing; let Claude Code show its own terminal UI.
    case passthrough
    /// Approve. `updatedInput` replaces the tool input (used to carry answers).
    case allow(updatedInput: JSONValue? = nil, updatedPermissions: [JSONValue]? = nil)
    /// Reject, optionally explaining why to Claude.
    case deny(message: String? = nil, interrupt: Bool = false)
    /// Keep Claude going after it stopped, with a follow-up instruction.
    case continueSession(prompt: String)
    /// Respond to an MCP elicitation form.
    case elicitation(action: ElicitationAction, content: JSONValue? = nil)
}

public enum ElicitationAction: String, Codable, Sendable {
    case accept, decline, cancel
}
