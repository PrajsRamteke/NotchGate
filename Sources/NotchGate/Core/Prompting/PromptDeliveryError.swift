import Foundation

/// Everything that can go wrong typing a prompt into a terminal, phrased so
/// it can be shown to the user as-is.
enum PromptDeliveryError: LocalizedError, Equatable {
    case emptyPrompt
    case tooLong(limit: Int)
    case sessionEnded
    case awaitingAnswer(String)
    case unsupportedTerminal(String)
    case automationDenied(app: String)
    case appNotRunning(String)
    case targetNotFound(String)
    case toolMissing(String)
    case editorHelperMissing(String)
    case commandFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Type a message first."
        case .tooLong(let limit):
            return "That message is too long (over \(limit) characters)."
        case .sessionEnded:
            return "This Claude session has ended."
        case .awaitingAnswer(let reason):
            return "Claude is waiting for you (\(reason.lowercased())). Answer that first, then send your message."
        case .unsupportedTerminal(let name):
            return "NotchGate can't type into \(name) yet. Supported: Terminal, iTerm, tmux, WezTerm, Cursor and VS Code."
        case .automationDenied(let app):
            return "macOS blocked NotchGate from controlling \(app). Allow it in System Settings → Privacy & Security → Automation."
        case .appNotRunning(let app):
            return "\(app) isn't running."
        case .targetNotFound(let place):
            return "Couldn't find this session's \(place). It may have been closed."
        case .toolMissing(let tool):
            return "Couldn't find the `\(tool)` command on this Mac."
        case .editorHelperMissing(let editor):
            return "The NotchGate helper isn't active in \(editor). Install it from the NotchGate menu, then reload the \(editor) window."
        case .commandFailed(let detail):
            return "Sending failed: \(detail)"
        case .timedOut(let what):
            return "\(what) didn't respond in time."
        }
    }
}
