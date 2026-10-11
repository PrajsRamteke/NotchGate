import Foundation

/// A Claude Code hook event name (`hook_event_name`).
///
/// Modeled as an open string wrapper so unknown future events decode
/// gracefully instead of failing the whole message.
public struct HookEvent: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let permissionRequest = HookEvent(rawValue: "PermissionRequest")
    public static let preToolUse = HookEvent(rawValue: "PreToolUse")
    public static let postToolUse = HookEvent(rawValue: "PostToolUse")
    public static let notification = HookEvent(rawValue: "Notification")
    public static let stop = HookEvent(rawValue: "Stop")
    public static let elicitation = HookEvent(rawValue: "Elicitation")
    public static let userPromptSubmit = HookEvent(rawValue: "UserPromptSubmit")
    public static let sessionEnd = HookEvent(rawValue: "SessionEnd")

    /// Events where the hook must wait for the app's decision before exiting.
    public var expectsReply: Bool {
        switch self {
        case .permissionRequest, .preToolUse, .stop, .elicitation: return true
        default: return false
        }
    }

    /// Every event NotchGate registers for in Claude Code settings.
    public static let subscribed: [HookEvent] = [
        .permissionRequest, .preToolUse, .elicitation, .stop,
        .postToolUse, .notification, .userPromptSubmit, .sessionEnd,
    ]
}
