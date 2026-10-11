import Foundation
import Testing
@testable import NotchGateKit

@Suite("HookOutput")
struct HookOutputTests {
    @Test func permissionAllowWithAlwaysRule() throws {
        let rule = JSONValue.object(["type": .string("addRules"), "destination": .string("localSettings")])
        let output = try #require(HookOutput.render(
            event: .permissionRequest,
            decision: .allow(updatedPermissions: [rule])
        ))
        let decision = try #require(output["hookSpecificOutput"]?["decision"])
        #expect(output["hookSpecificOutput"]?["hookEventName"] == .string("PermissionRequest"))
        #expect(decision["behavior"] == .string("allow"))
        #expect(decision["updatedPermissions"] == .array([rule]))
        #expect(decision["updatedInput"] == nil)
    }

    @Test func permissionDenyCarriesMessage() throws {
        let output = try #require(HookOutput.render(
            event: .permissionRequest,
            decision: .deny(message: "Use the staging DB", interrupt: true)
        ))
        let decision = try #require(output["hookSpecificOutput"]?["decision"])
        #expect(decision["behavior"] == .string("deny"))
        #expect(decision["message"] == .string("Use the staging DB"))
        #expect(decision["interrupt"] == .bool(true))
    }

    @Test func preToolUseAllowCarriesAnswers() throws {
        let input = JSONValue.object(["answers": .object(["Q?": .string("A")])])
        let output = try #require(HookOutput.render(event: .preToolUse, decision: .allow(updatedInput: input)))
        let specific = try #require(output["hookSpecificOutput"])
        #expect(specific["permissionDecision"] == .string("allow"))
        #expect(specific["updatedInput"] == input)
    }

    @Test func preToolUseDenyUsesReason() throws {
        let output = try #require(HookOutput.render(event: .preToolUse, decision: .deny(message: "Keep planning")))
        #expect(output["hookSpecificOutput"]?["permissionDecision"] == .string("deny"))
        #expect(output["hookSpecificOutput"]?["permissionDecisionReason"] == .string("Keep planning"))
    }

    @Test func stopContinueBlocksWithReason() throws {
        let output = try #require(HookOutput.render(event: .stop, decision: .continueSession(prompt: "Now add tests")))
        #expect(output == .object(["decision": .string("block"), "reason": .string("Now add tests")]))
    }

    @Test func elicitationAcceptIncludesContentOnlyOnAccept() throws {
        let content = JSONValue.object(["name": .string("alice")])
        let accept = try #require(HookOutput.render(event: .elicitation, decision: .elicitation(action: .accept, content: content)))
        #expect(accept["hookSpecificOutput"]?["content"] == content)

        let decline = try #require(HookOutput.render(event: .elicitation, decision: .elicitation(action: .decline, content: content)))
        #expect(decline["hookSpecificOutput"]?["action"] == .string("decline"))
        #expect(decline["hookSpecificOutput"]?["content"] == nil)
    }

    @Test func rewakeCarriesThePromptOnly() {
        let message = HookOutput.rewakeMessage(for: .continueSession(prompt: "add tests"))
        #expect(message?.hasPrefix("add tests\n") == true)
        #expect(message?.contains("NotchGate") == true)
        #expect(HookOutput.rewakeMessage(for: .passthrough) == nil)
        #expect(HookOutput.rewakeExitCode == 2)
        #expect(BridgeRequest(event: .stopRewake, payload: .object([:]), origin: ProcessOrigin(claudePID: 1)).expectsReply)
    }

    @Test func passthroughAndMismatchesPrintNothing() {
        #expect(HookOutput.render(event: .permissionRequest, decision: .passthrough) == nil)
        #expect(HookOutput.render(event: .stop, decision: .allow()) == nil)
        #expect(HookOutput.render(event: .notification, decision: .deny()) == nil)
    }
}
