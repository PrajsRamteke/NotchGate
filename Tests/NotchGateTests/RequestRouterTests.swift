import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("RequestRouter")
struct RequestRouterTests {
    /// Every request type switched on, so each route can be exercised.
    private let router = RequestRouter(options: .init(
        replyFromNotch: false, showNotices: true, questionMode: .notch, showFileEdits: true, showPlans: true
    ))

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

    @Test func stopIsANoticeWhenTheComposerIsOff() {
        let stop = message(.stop, ["last_assistant_message": .string("All done")])
        guard case .notice(let notice) = router.route(stop) else {
            Issue.record("Expected a notice")
            return
        }
        #expect(notice.message == "All done")
        // With the composer on, the background Stop hook owns the summary.
        #expect(RequestRouter(options: .init(replyFromNotch: true, showNotices: true)).route(stop) == .ignore)
    }

    @Test func backgroundStopBecomesAComposer() {
        let route = router.route(message(.stopRewake, ["last_assistant_message": .string("Done")]))
        guard case .present(let request) = route, case .completion(let prompt) = request.kind else {
            Issue.record("Expected a composer")
            return
        }
        #expect(prompt.summary == "Done")
    }

    @Test func notificationsAreFiltered() {
        // Normally answered by the PermissionRequest card: only a fallback alert.
        guard case .attentionIfUnseen(let fallback) = router.route(message(.notification, ["notification_type": .string("permission_prompt")])) else {
            Issue.record("Expected a fallback alert")
            return
        }
        #expect(fallback.blocksClaude)
        #expect(router.route(message(.notification, ["notification_type": .string("elicitation_complete")])) == .ignore)
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

    @Test func stopIsSilentWhenNoticesAreOff() {
        let quiet = RequestRouter(options: .init(replyFromNotch: false, showNotices: false))
        #expect(quiet.route(message(.stop, ["last_assistant_message": .string("Done")])) == .ignore)
    }

    @Test func defaultsShowOnlyPermissions() {
        let defaults = RequestRouter(options: .init())
        guard case .present = defaults.route(message(.permissionRequest, ["tool_name": .string("Bash")])) else {
            Issue.record("Permissions should be on by default")
            return
        }
        let question = message(.preToolUse, ["tool_name": .string("AskUserQuestion"), "tool_input": .object([
            "questions": .array([.object(["question": .string("Q?"), "options": .array([.object(["label": .string("A")])])])]),
        ])])
        // Switched off: answered in the terminal, but the notch still alerts.
        for route in [
            defaults.route(message(.permissionRequest, ["tool_name": .string("Edit")])),
            defaults.route(message(.preToolUse, ["tool_name": .string("ExitPlanMode")])),
            defaults.route(question),
        ] {
            guard case .attention(let notice) = route else {
                Issue.record("Expected an alert, got \(route)")
                continue
            }
            #expect(notice.blocksClaude)
        }
    }

    @Test func questionAlertShowsTheQuestionAndEndsWhenAnswered() {
        let question = message(.preToolUse, ["tool_name": .string("AskUserQuestion"), "tool_input": .object([
            "questions": .array([.object(["question": .string("Q?"), "options": .array([.object(["label": .string("A")])])])]),
        ])])
        guard case .attention(let notice) = RequestRouter(options: .init(questionMode: .terminal)).route(question) else {
            Issue.record("Expected an alert")
            return
        }
        #expect(notice.message == "**Q?**\n- A")
        // The answered call comes back with `answers` added, so any call of the tool ends it.
        #expect(notice.waitingOn?.isFinished(by: "AskUserQuestion", input: .object(["answers": .object([:])])) == true)
        #expect(notice.waitingOn?.isFinished(by: "Bash", input: .object([:])) == false)
    }

    @Test func unreadableQuestionStillAlerts() {
        let broken = message(.preToolUse, ["tool_name": .string("AskUserQuestion"), "tool_input": .object([:])])
        guard case .attention = router.route(broken) else {
            Issue.record("A question the card can't show must still alert")
            return
        }
    }

    @Test func questionsTurnedOffNeverAlert() {
        let off = RequestRouter(options: .init(questionMode: .off))
        #expect(off.route(message(.preToolUse, ["tool_name": .string("AskUserQuestion")]))
            == .autoRespond(.deny(message: QuestionMode.declineMessage)))
    }

    @Test func permissionsSwitchedOffAreLeftToTheTerminal() {
        let off = RequestRouter(options: .init(showPermissions: false, showFileEdits: true))
        let input = JSONValue.object(["command": .string("git push")])
        guard case .attention(let notice) = off.route(message(.permissionRequest, ["tool_name": .string("Bash"), "tool_input": input])) else {
            Issue.record("Expected an alert for a permission answered in the terminal")
            return
        }
        #expect(notice.waitingOn == Notice.Wait(toolName: "Bash", input: input))
        guard case .present = off.route(message(.permissionRequest, ["tool_name": .string("Write")])) else {
            Issue.record("File edits are switched on independently")
            return
        }
    }

    @Test func userReturningClearsSession() {
        #expect(router.route(message(.userPromptSubmit, [:])) == .clearSession("s1"))
        #expect(router.route(message(.sessionEnd, [:])) == .clearSession("s1"))
    }
}
