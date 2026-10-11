import Foundation

/// Rules shared by the hook and the app about which messages block Claude
/// and how much of each payload crosses the socket.
public enum HookPolicy {
    /// Tools whose `PreToolUse` the user answers from the notch. Every other
    /// tool's `PreToolUse` is fire-and-forget activity tracking.
    public static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Tools whose small `tool_response` is kept so task progress can be tracked.
    static let responseTools: Set<String> = ["TaskCreate"]

    /// Tools that create or change files; their `tool_response` is boiled down
    /// to a `file_change` summary (see `fileChange(tool:input:response:)`).
    public static let fileTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]

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
            if fileTools.contains(tool), let change = fileChange(tool: tool, input: payload["tool_input"], response: response) {
                trimmed = trimmed.setting("file_change", to: change)
            }
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

// MARK: - File changes

public extension HookPolicy {
    /// What a successful file tool did, small enough for the socket:
    /// `{"created": Bool, "lines_added": Int, "lines_removed": Int}`.
    ///
    /// Must run on the full payload: line counts come from the diff Claude Code
    /// reports (`structuredPatch`) or, for a new file, from its whole content.
    static func fileChange(tool: String, input: JSONValue?, response: JSONValue) -> JSONValue? {
        guard response.objectValue != nil else { return nil }
        let created = response["type"]?.stringValue == "create"
        var added = 0, removed = 0
        for hunk in response["structuredPatch"]?.arrayValue ?? [] {
            for line in hunk["lines"]?.arrayValue ?? [] {
                guard let text = line.stringValue else { continue }
                if text.hasPrefix("+") { added += 1 } else if text.hasPrefix("-") { removed += 1 }
            }
        }
        if created, added == 0, let content = input?["content"]?.stringValue ?? response["content"]?.stringValue {
            added = lineCount(content)
        }
        return .object([
            "created": .bool(created),
            "lines_added": .number(Double(added)),
            "lines_removed": .number(Double(removed)),
        ])
    }

    private static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let breaks = text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        return text.hasSuffix("\n") ? breaks : breaks + 1
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
