import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("RequestRouter")
struct RequestRouterTests {
    private let router = RequestRouter(options: .init(holdForReplyOnStop: false, replyWindow: 30, showNotices: true))

    private func message(_ event: HookEvent, _ fields: [String: JSONValue]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string("s1")
        payload["cwd"] = .string("/tmp/project")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 7))
    }

    @Test func permissionRequestBecomesPermissionCard() throws {
        let route = router.route(message(.permissionRequest, [
            "tool_name": .string("Bash"),
            "tool_input": .object(["command": .string("ls")]),
            "permission_suggestions": .array([.object(["type": .string("addRules")])]),
        ]))
        guard case .present(let request) = route, case .permission(let permission) = request.kind else {
            Issue.record("Expected a permission card, got \(route)")
            return
        }
        #expect(permission.toolName == "Bash")
        #expect(permission.suggestions.count == 1)
        #expect(request.session.projectName == "project")
        #expect(request.session.claudePID == 7)
    }

    @Test func interactiveToolsAreIgnoredInPermissionRequest() {
        let route = router.route(message(.permissionRequest, ["tool_name": .string("AskUserQuestion")]))
        #expect(route == .ignore)
    }

    @Test func askUserQuestionParsesOptions() throws {
        let route = router.route(message(.preToolUse, [
            "tool_name": .string("AskUserQuestion"),
            "tool_input": .object(["questions": .array([.object([
                "question": .string("Pick one"),
                "multiSelect": .bool(true),
                "options": .array([.object(["label": .string("A")]), .object(["label": .string("B")])]),
            ])])]),
        ]))
        guard case .present(let request) = route, case .question(let prompt) = request.kind else {
            Issue.record("Expected a question card")
            return
        }
        #expect(prompt.questions.first?.options.map(\.label) == ["A", "B"])
        #expect(prompt.questions.first?.multiSelect == true)
    }

    @Test func exitPlanModeBecomesPlanCard() {
        let route = router.route(message(.preToolUse, [
            "tool_name": .string("ExitPlanMode"),
            "tool_input": .object(["plan": .string("## Plan")]),
        ]))
        guard case .present(let request) = route, case .plan(let plan) = request.kind else {
            Issue.record("Expected a plan card")
            return
        }
        #expect(plan.markdown == "## Plan")
    }

    @Test func stopIsANoticeUnlessHolding() {
        let stop = message(.stop, ["last_assistant_message": .string("All done")])
        guard case .notice(let notice) = router.route(stop) else {
            Issue.record("Expected a notice")
            return
        }
        #expect(notice.message == "All done")

        let holding = RequestRouter(options: .init(holdForReplyOnStop: true, replyWindow: 30, showNotices: true))
        let now = Date()
        guard case .present(let request) = holding.route(stop, now: now) else {
            Issue.record("Expected a completion card")
            return
        }
        #expect(request.expiresAt == now.addingTimeInterval(30))
    }

    @Test func notificationsAreFiltered() {
        #expect(router.route(message(.notification, ["notification_type": .string("permission_prompt")])) == .ignore)
        guard case .notice(let notice) = router.route(message(.notification, ["notification_type": .string("idle_prompt")])) else {
            Issue.record("Expected an idle notice")
            return
        }
        #expect(notice.tone == .attention)
    }

    @Test func completedToolsAndStopsRetireStaleCards() {
        let input = JSONValue.object(["command": .string("git status")])
        let route = router.route(message(.postToolUse, ["tool_name": .string("Bash"), "tool_input": input]))
        #expect(route == .toolCompleted(sessionID: "s1", toolName: "Bash", input: input))
        #expect(RequestRouter.clearsSessionFirst(.stop))
        #expect(!RequestRouter.clearsSessionFirst(.permissionRequest))
    }

    @Test func replyCardIsNeverOfferedTwiceInARow() {
        let holding = RequestRouter(options: .init(holdForReplyOnStop: true, replyWindow: 30, showNotices: false))
        let continuation = message(.stop, ["stop_hook_active": .bool(true)])
        #expect(holding.route(continuation) == .ignore)
    }

    @Test func stopIsSilentWhenNoticesAreOff() {
        let quiet = RequestRouter(options: .init(holdForReplyOnStop: false, replyWindow: 30, showNotices: false))
        #expect(quiet.route(message(.stop, ["last_assistant_message": .string("Done")])) == .ignore)
    }

    @Test func userReturningClearsSession() {
        #expect(router.route(message(.userPromptSubmit, [:])) == .clearSession("s1"))
        #expect(router.route(message(.sessionEnd, [:])) == .clearSession("s1"))
    }
}
