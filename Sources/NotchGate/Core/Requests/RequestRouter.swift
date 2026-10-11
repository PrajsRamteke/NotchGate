import Foundation
import NotchGateKit

/// What the app should do with an incoming hook message.
enum RequestRoute: Equatable {
    /// Show an interactive card and wait for the user.
    case present(ClaudeRequest)
    /// Show a transient notice; reply `.passthrough` if the hook is waiting.
    case notice(Notice)
    /// The user is back at the terminal for this session; clear stale cards.
    case clearSession(String)
    /// A tool finished, so any card still asking about it was answered elsewhere.
    case toolCompleted(sessionID: String, toolName: String, input: JSONValue)
    /// Not ours to handle; reply `.passthrough` if the hook is waiting.
    case ignore
}

/// Decides how each hook event is presented. Pure and deterministic, so it
/// is fully unit-testable without any UI.
struct RequestRouter {
    struct Options {
        var holdForReplyOnStop: Bool
        var replyWindow: TimeInterval
        var showNotices: Bool
    }

    var options: Options

    func route(_ message: BridgeRequest, now: Date = .now) -> RequestRoute {
        let payload = message.payload
        let session = SessionInfo(
            id: payload["session_id"]?.stringValue ?? "unknown",
            cwd: payload["cwd"]?.stringValue ?? "",
            claudePID: message.origin.claudePID
        )

        func present(_ kind: RequestKind, expiresAt: Date? = nil) -> RequestRoute {
            .present(ClaudeRequest(
                id: message.id, event: message.event, session: session,
                kind: kind, receivedAt: now, expiresAt: expiresAt
            ))
        }

        func notice(_ title: String, _ body: String?, _ tone: Notice.Tone) -> RequestRoute {
            options.showNotices ? .notice(Notice(session: session, title: title, message: body, tone: tone)) : .ignore
        }

        let toolName = payload["tool_name"]?.stringValue ?? ""
        let toolInput = payload["tool_input"] ?? .object([:])

        switch message.event {
        case .permissionRequest:
            // Interactive tools are answered through PreToolUse. If one reaches
            // PermissionRequest, the user chose the terminal: stay out of the way.
            guard !Self.interactiveTools.contains(toolName) else { return .ignore }
            let suggestions = payload["permission_suggestions"]?.arrayValue ?? []
            return present(.permission(ToolPermission(toolName: toolName, input: toolInput, suggestions: suggestions)))

        case .preToolUse where toolName == "AskUserQuestion":
            guard let prompt = PayloadParsers.question(from: toolInput) else { return .ignore }
            return present(.question(prompt))

        case .preToolUse where toolName == "ExitPlanMode":
            return present(.plan(PayloadParsers.plan(from: toolInput)))

        case .elicitation:
            return present(.elicitation(PayloadParsers.elicitation(from: payload)))

        case .stop:
            let summary = payload["last_assistant_message"]?.stringValue
            // `stop_hook_active` means Claude is only running because of an earlier
            // notch reply. Offering another card then would chain replies forever.
            let isContinuation = payload["stop_hook_active"]?.boolValue == true
            guard options.holdForReplyOnStop, !isContinuation else { return notice("Claude finished", summary, .done) }
            return present(.completion(CompletionPrompt(summary: summary)),
                           expiresAt: now.addingTimeInterval(options.replyWindow))

        case .notification:
            return routeNotification(payload, notice: notice)

        case .postToolUse:
            return .toolCompleted(sessionID: session.id, toolName: toolName, input: toolInput)

        case .userPromptSubmit, .sessionEnd:
            return .clearSession(session.id)

        default:
            return .ignore
        }
    }

    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// When Claude stops, nothing it asked earlier in the turn can still be
    /// pending, so those cards are cleared before the Stop itself is handled.
    static func clearsSessionFirst(_ event: HookEvent) -> Bool {
        event == .stop
    }

    private func routeNotification(
        _ payload: JSONValue,
        notice: (String, String?, Notice.Tone) -> RequestRoute
    ) -> RequestRoute {
        let type = payload["notification_type"]?.stringValue ?? ""
        let message = payload["message"]?.stringValue
        switch type {
        // Already surfaced as interactive cards by dedicated hooks.
        case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog",
             "elicitation_complete", "elicitation_response":
            return .ignore
        case "idle_prompt", "agent_needs_input":
            return notice("Claude is waiting for you", message, .attention)
        case "agent_completed":
            return notice("Agent finished", message, .done)
        default:
            return notice(payload["title"]?.stringValue ?? "Claude", message, .info)
        }
    }
}
