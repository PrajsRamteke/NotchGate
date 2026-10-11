import Foundation

/// Translates a `BridgeDecision` into the stdout JSON Claude Code expects
/// for a given hook event. Returns `nil` when the hook should print nothing,
/// which leaves Claude Code's normal behavior untouched.
///
/// Reference: https://code.claude.com/docs/en/hooks
public enum HookOutput {
    public static func render(event: HookEvent, decision: BridgeDecision) -> JSONValue? {
        switch (event, decision) {
        case (_, .passthrough):
            return nil

        case (.permissionRequest, .allow(let input, let permissions)):
            var body: [String: JSONValue] = ["behavior": .string("allow")]
            if let input { body["updatedInput"] = input }
            if let permissions, !permissions.isEmpty { body["updatedPermissions"] = .array(permissions) }
            return specific(.permissionRequest, ["decision": .object(body)])

        case (.permissionRequest, .deny(let message, let interrupt)):
            var body: [String: JSONValue] = ["behavior": .string("deny")]
            body["message"] = .string(message ?? "Denied from NotchGate")
            if interrupt { body["interrupt"] = .bool(true) }
            return specific(.permissionRequest, ["decision": .object(body)])

        case (.preToolUse, .allow(let input, _)):
            var body: [String: JSONValue] = ["permissionDecision": .string("allow")]
            if let input { body["updatedInput"] = input }
            return specific(.preToolUse, body)

        case (.preToolUse, .deny(let message, _)):
            return specific(.preToolUse, [
                "permissionDecision": .string("deny"),
                "permissionDecisionReason": .string(message ?? "Rejected from NotchGate"),
            ])

        case (.stop, .continueSession(let prompt)):
            return .object(["decision": .string("block"), "reason": .string(prompt)])

        case (.elicitation, .elicitation(let action, let content)):
            var body: [String: JSONValue] = ["action": .string(action.rawValue)]
            if action == .accept, let content { body["content"] = content }
            return specific(.elicitation, body)

        default:
            // A decision that doesn't apply to this event: fail safe and stay silent.
            return nil
        }
    }

    private static func specific(_ event: HookEvent, _ fields: [String: JSONValue]) -> JSONValue {
        var output = fields
        output["hookEventName"] = .string(event.rawValue)
        return .object(["hookSpecificOutput": .object(output)])
    }
}
