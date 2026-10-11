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
    /// When set, the request auto-resolves with `.passthrough` at this time.
    let expiresAt: Date?

    init(
        id: UUID,
        event: HookEvent,
        session: SessionInfo,
        kind: RequestKind,
        receivedAt: Date = .now,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.event = event
        self.session = session
        self.kind = kind
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
    }
}

/// A transient, non-blocking message (e.g. "Claude finished").
struct Notice: Identifiable, Equatable, Sendable {
    enum Tone: Sendable { case attention, done, info }

    let id = UUID()
    let session: SessionInfo
    let title: String
    let message: String?
    let tone: Tone
}
