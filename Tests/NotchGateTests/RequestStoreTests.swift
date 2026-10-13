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

    private func alert(_ tool: String = "Bash", session: String = "s1") -> Notice {
        Notice(session: SessionInfo(id: session, cwd: "/tmp", claudePID: 1), title: "Waiting", message: nil,
               tone: .attention, waitingOn: .init(toolName: tool, input: .object(["command": .string("git push")])))
    }

    @Test func alertStaysUntilItsToolFinishes() {
        let store = RequestStore()
        var alerted: [Notice] = []
        store.onAlert = { alerted.append($0) }
        store.post(alert())
        #expect(alerted.count == 1)
        #expect(store.isAlerting(for: "s1"))

        // A passing notice never covers it.
        store.post(Notice(session: SessionInfo(id: "s2", cwd: "/tmp", claudePID: 2), title: "Done", message: nil, tone: .done))
        #expect(store.notice?.blocksClaude == true)

        store.dismissCompletedTool(sessionID: "s1", toolName: "Bash", input: .object(["command": .string("ls")]))
        #expect(store.notice != nil)
        store.dismissCompletedTool(sessionID: "s1", toolName: "Bash", input: .object(["command": .string("git push")]))
        #expect(store.notice == nil)
    }

    @Test func returningToTheSessionClearsItsAlert() {
        let store = RequestStore()
        store.post(alert())
        store.clearSession("s1")
        #expect(store.notice == nil)
        #expect(!store.isAlerting(for: "s1"))
    }

    @Test func otherSessionsAreUntouched() {
        let store = RequestStore()
        store.enqueue(permission("git status", session: "s2"), responder: Recorder())
        store.dismissCompletedTool(sessionID: "s1", toolName: "Bash", input: .object(["command": .string("git status")]))
        #expect(store.pendingCount == 1)
    }

    private func composer(_ session: String = "s1") -> ClaudeRequest {
        ClaudeRequest(id: UUID(), event: .stopRewake, session: SessionInfo(id: session, cwd: "/tmp", claudePID: 1),
                      kind: .completion(CompletionPrompt(summary: nil)))
    }

    @Test func promptGoesStraightToAWaitingSession() {
        let store = RequestStore()
        let hook = Recorder()
        store.enqueue(composer(), responder: hook)
        #expect(store.sendPrompt("ship it", to: "s1") == .sent)
        #expect(hook.decisions == [.continueSession(prompt: "ship it")])
        #expect(!store.hasPending)
    }

    @Test func promptForABusySessionIsQueued() {
        let store = RequestStore()
        #expect(store.sendPrompt("next", to: "s1") == .queued)
        #expect(store.queuedPrompts["s1"] == "next")
        #expect(store.takeQueuedPrompt(for: "s1") == "next")
        #expect(store.queuedPrompts.isEmpty)
    }

    @Test func parkedComposerFreesTheIslandButStaysReachable() throws {
        let store = RequestStore()
        let request = composer()
        store.enqueue(request, responder: Recorder())
        store.park(request.id)
        #expect(store.current == nil)
        #expect(try #require(store.composer(for: "s1")).id == request.id)
    }

    @Test func newerComposerReplacesOlderOneAndStopKeepsIt() {
        let store = RequestStore()
        let old = Recorder()
        store.enqueue(composer(), responder: old)
        store.enqueue(composer(), responder: Recorder())
        #expect(old.decisions == [.passthrough])
        store.clearSession("s1", keepingComposer: true)
        #expect(store.composer(for: "s1") != nil)
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
