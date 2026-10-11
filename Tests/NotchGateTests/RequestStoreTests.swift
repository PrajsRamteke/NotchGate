import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("RequestStore")
@MainActor
struct RequestStoreTests {
    private final class Recorder: DecisionResponder, @unchecked Sendable {
        var decisions: [BridgeDecision] = []
        func send(_ decision: BridgeDecision) { decisions.append(decision) }
    }

    private func permission(_ command: String, session: String = "s1") -> ClaudeRequest {
        ClaudeRequest(
            id: UUID(),
            event: .permissionRequest,
            session: SessionInfo(id: session, cwd: "/tmp", claudePID: 1),
            kind: .permission(ToolPermission(
                toolName: "Bash",
                input: .object(["command": .string(command)]),
                suggestions: []
            ))
        )
    }

    @Test func toolThatAlreadyRanDismissesOnlyItsOwnCard() {
        let store = RequestStore()
        let answered = Recorder()
        let other = Recorder()
        store.enqueue(permission("git status"), responder: answered)
        store.enqueue(permission("npm test"), responder: other)

        store.dismissCompletedTool(sessionID: "s1", toolName: "Bash", input: .object(["command": .string("git status")]))

        #expect(store.pendingCount == 1)
        #expect(answered.decisions == [.passthrough])
        #expect(other.decisions.isEmpty)
    }

    @Test func otherSessionsAreUntouched() {
        let store = RequestStore()
        store.enqueue(permission("git status", session: "s2"), responder: Recorder())
        store.dismissCompletedTool(sessionID: "s1", toolName: "Bash", input: .object(["command": .string("git status")]))
        #expect(store.pendingCount == 1)
    }

    @Test func clearingASessionReleasesItsHooks() {
        let store = RequestStore()
        let recorder = Recorder()
        store.enqueue(permission("ls"), responder: recorder)
        store.clearSession("s1")
        #expect(!store.hasPending)
        #expect(recorder.decisions == [.passthrough])
    }
}
