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
    /// Answer immediately without showing anything (auto-allow, questions off).
    case autoRespond(BridgeDecision)
    /// Not ours to handle; reply `.passthrough` if the hook is waiting.
    case ignore
}

/// Decides how each hook event is presented. Pure and deterministic, so it
/// is fully unit-testable without any UI.
struct RequestRouter {
    struct Options {
        var replyFromNotch = true
        var showNotices = false
        var autoAllowPermissions = false
        var askForRiskyCommands = true
        var questionMode: QuestionMode = .terminal
        var showPermissions = true
        var showFileEdits = false
        var showPlans = false
    }

    static let fileEditTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    var options: Options

    func route(_ message: BridgeRequest, now: Date = .now) -> RequestRoute {
        let payload = message.payload
        let session = SessionInfo(
            id: payload["session_id"]?.stringValue ?? "unknown",
            cwd: payload["cwd"]?.stringValue ?? "",
            claudePID: message.origin.claudePID
        )

        func present(_ kind: RequestKind) -> RequestRoute {
            .present(ClaudeRequest(id: message.id, event: message.event, session: session, kind: kind, receivedAt: now))
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
            guard !HookPolicy.interactiveTools.contains(toolName) else { return .ignore }
            // A type switched off in "Show in notch" is left entirely to the terminal.
            let isFileEdit = Self.fileEditTools.contains(toolName)
            guard isFileEdit ? options.showFileEdits : options.showPermissions else { return .ignore }
            let suggestions = payload["permission_suggestions"]?.arrayValue ?? []
            let permission = ToolPermission(toolName: toolName, input: toolInput, suggestions: suggestions)
            if shouldAutoAllow(permission) { return .autoRespond(.allow()) }
            return present(.permission(permission))

        case .preToolUse where toolName == "AskUserQuestion":
            switch options.questionMode {
            case .terminal: return .ignore
            case .off: return .autoRespond(.deny(message: QuestionMode.declineMessage))
            case .notch: break
            }
            guard let prompt = PayloadParsers.question(from: toolInput) else { return .ignore }
            return present(.question(prompt))

        case .preToolUse where toolName == "ExitPlanMode":
            guard options.showPlans else { return .ignore }
            return present(.plan(PayloadParsers.plan(from: toolInput)))

        case .elicitation:
            return present(.elicitation(PayloadParsers.elicitation(from: payload)))

        case .stop:
            // With the composer on, the background Stop hook shows the summary.
            guard !options.replyFromNotch else { return .ignore }
            return notice("Claude finished", payload["last_assistant_message"]?.stringValue, .done)

        case .stopRewake:
            return present(.completion(CompletionPrompt(summary: payload["last_assistant_message"]?.stringValue)))

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

    func shouldAutoAllow(_ permission: ToolPermission) -> Bool {
        options.autoAllowPermissions && !(options.askForRiskyCommands && RiskPolicy.isRisky(permission))
    }

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
