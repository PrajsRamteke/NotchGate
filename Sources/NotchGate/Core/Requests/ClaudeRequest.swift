import Foundation
import NotchGateKit

/// The Claude Code session a request belongs to.
struct SessionInfo: Equatable, Sendable {
    let id: String
    let cwd: String
    let claudePID: Int32

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }
}

/// Something Claude is blocked on until the user responds.
struct ClaudeRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let event: HookEvent
    let session: SessionInfo
    let kind: RequestKind
    let receivedAt: Date

    init(
        id: UUID,
        event: HookEvent,
        session: SessionInfo,
        kind: RequestKind,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.event = event
        self.session = session
        self.kind = kind
        self.receivedAt = receivedAt
    }
}

/// A message in the notch. Usually transient (e.g. "Claude finished"); when
/// `waitingOn` is set, Claude is blocked in the terminal on the user, so the
/// notice opens the notch and stays until that wait is over.
struct Notice: Identifiable, Equatable, Sendable {
    enum Tone: Sendable { case attention, done, info }

    /// The tool call Claude is blocked on. `toolName` is nil when only a
    /// Notification said so (any finished tool ends that wait); `input` is nil
    /// to match any call of the tool.
    struct Wait: Equatable, Sendable {
        var toolName: String?
        var input: JSONValue?

        func isFinished(by toolName: String, input: JSONValue) -> Bool {
            guard let expected = self.toolName else { return true }
            return expected == toolName && (self.input == nil || self.input == input)
        }
    }

    let id = UUID()
    let session: SessionInfo
    let title: String
    let message: String?
    let tone: Tone
    var waitingOn: Wait?

    init(session: SessionInfo, title: String, message: String?, tone: Tone, waitingOn: Wait? = nil) {
        self.session = session
        self.title = title
        self.message = message
        self.tone = tone
        self.waitingOn = waitingOn
    }

    var blocksClaude: Bool { waitingOn != nil }
}
