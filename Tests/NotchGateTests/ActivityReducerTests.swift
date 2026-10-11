import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("ActivityReducer")
struct ActivityReducerTests {
    private func event(_ event: HookEvent, _ fields: [String: JSONValue] = [:]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string("s1")
        payload["cwd"] = .string("/tmp/shop")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 9))
    }

    private func run(_ events: [BridgeRequest]) -> SessionActivity? {
        events.reduce([:]) { ActivityReducer.reduce($0, $1) }["s1"]
    }

    @Test func turnLifecycle() throws {
        let session = try #require(run([
            event(.userPromptSubmit, ["prompt": .string("fix the build")]),
            event(.preToolUse, ["tool_name": .string("Bash"), "tool_input": .object(["command": .string("make")])]),
        ]))
        #expect(session.projectName == "shop")
        #expect(session.prompt == "fix the build")
        #expect(session.toolCount == 1)
        guard case .running(let step) = session.phase else {
            Issue.record("expected running")
            return
        }
        #expect(step.summary == "Running make")
        #expect(session.isWorking)

        let done = try #require(run([
            event(.userPromptSubmit), event(.stop, ["last_assistant_message": .string("Fixed")]),
        ]))
        #expect(done.phase == .finished)
        #expect(done.lastMessage == "Fixed")
        #expect(done.turnEndedAt != nil)
    }

    @Test func waitingStates() {
        let permission = run([event(.permissionRequest, ["tool_name": .string("Write"), "tool_input": .object(["file_path": .string("/a/b.txt")])])])
        #expect(permission?.phase == .waiting(reason: "Needs permission · Writing b.txt"))
        let question = run([event(.preToolUse, ["tool_name": .string("AskUserQuestion")])])
        #expect(question?.phase == .waiting(reason: "Asking you a question"))
    }

    @Test func todoWriteBecomesProgress() throws {
        let todos = JSONValue.object(["todos": .array([
            .object(["content": .string("A"), "status": .string("completed")]),
            .object(["content": .string("B"), "status": .string("in_progress"), "activeForm": .string("Doing B")]),
            .object(["content": .string("C"), "status": .string("pending")]),
        ])])
        let progress = try #require(run([event(.preToolUse, ["tool_name": .string("TodoWrite"), "tool_input": todos])])?.progress)
        #expect(progress.completed == 1)
        #expect(progress.total == 3)
        #expect(progress.current == "Doing B")
    }

    @Test func taskToolsTrackProgress() throws {
        let session = try #require(run([
            event(.postToolUse, ["tool_name": .string("TaskCreate"), "tool_input": .object(["subject": .string("Write tests")]),
                                 "tool_response": .object(["task": .object(["id": .string("7")])])]),
            event(.postToolUse, ["tool_name": .string("TaskCreate"), "tool_input": .object(["subject": .string("Ship")])]),
            event(.postToolUse, ["tool_name": .string("TaskUpdate"), "tool_input": .object(["taskId": .string("7"), "status": .string("completed")])]),
        ]))
        #expect(session.tasks.map(\.id) == ["7", "2"])
        #expect(session.progress?.completed == 1)
    }

    @Test func sessionEndRemovesSession() {
        #expect(run([event(.userPromptSubmit), event(.sessionEnd)]) == nil)
    }

    @Test func activityEventsNeverBlockClaude() {
        let bash = event(.preToolUse, ["tool_name": .string("Bash")])
        #expect(!bash.expectsReply)
        #expect(event(.preToolUse, ["tool_name": .string("AskUserQuestion")]).expectsReply)
        #expect(!event(.sessionStart).expectsReply)
        #expect(!event(.preCompact).expectsReply)
    }

    @Test func largePayloadsAreTrimmedButInteractiveOnesAreNot() {
        let huge = String(repeating: "x", count: HookPolicy.maxStringLength * 2)
        let write = JSONValue.object(["tool_name": .string("Write"), "tool_input": .object(["content": .string(huge)]),
                                      "tool_response": .string(huge)])
        let trimmed = HookPolicy.sanitize(event: .postToolUse, payload: write)
        #expect(trimmed["tool_response"] == nil)
        #expect((trimmed["tool_input"]?["content"]?.stringValue?.count ?? 0) <= HookPolicy.maxStringLength + 1)

        let plan = JSONValue.object(["tool_name": .string("ExitPlanMode"), "tool_input": .object(["plan": .string(huge)])])
        #expect(HookPolicy.sanitize(event: .preToolUse, payload: plan) == plan)
    }
}
