import Foundation

/// Rules shared by the hook and the app about which messages block Claude
/// and how much of each payload crosses the socket.
public enum HookPolicy {
    /// Tools whose `PreToolUse` the user answers from the notch. Every other
    /// tool's `PreToolUse` is fire-and-forget activity tracking.
    public static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Tools whose small `tool_response` is kept so task progress can be tracked.
    static let responseTools: Set<String> = ["TaskCreate"]

    /// Longest string kept from activity payloads. Big file bodies (e.g. `Write`)
    /// are useless for a status line and would only slow the socket down.
    public static let maxStringLength = 4_000

    public static func expectsReply(event: HookEvent, payload: JSONValue) -> Bool {
        guard event == .preToolUse else { return event.expectsReply }
        return interactiveTools.contains(payload["tool_name"]?.stringValue ?? "")
    }

    /// Trims a payload before sending it. Interactive payloads stay intact
    /// because they are echoed back to Claude as `updatedInput`.
    public static func sanitize(event: HookEvent, payload: JSONValue) -> JSONValue {
        let isInteractiveToolUse = event == .preToolUse && expectsReply(event: event, payload: payload)
        if event == .elicitation || isInteractiveToolUse { return payload }
        var trimmed = payload
        let tool = payload["tool_name"]?.stringValue ?? ""
        if let response = payload["tool_response"] {
            trimmed = responseTools.contains(tool)
                ? trimmed.setting("tool_response", to: response.truncatingStrings(to: maxStringLength))
                : trimmed.removing("tool_response")
        }
        if let input = payload["tool_input"] {
            trimmed = trimmed.setting("tool_input", to: input.truncatingStrings(to: maxStringLength))
        }
        return trimmed
    }
}

public extension JSONValue {
    /// Copy with every string longer than `limit` characters cut short.
    func truncatingStrings(to limit: Int) -> JSONValue {
        switch self {
        case .string(let value) where value.count > limit:
            return .string(String(value.prefix(limit)) + "…")
        case .array(let values):
            return .array(values.map { $0.truncatingStrings(to: limit) })
        case .object(let values):
            return .object(values.mapValues { $0.truncatingStrings(to: limit) })
        default:
            return self
        }
    }
}
