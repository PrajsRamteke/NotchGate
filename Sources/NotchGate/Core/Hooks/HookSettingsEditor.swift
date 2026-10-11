import Foundation
import NotchGateKit

/// Pure transformations of a Claude Code `settings.json` document that add or
/// remove NotchGate's hook entries without touching anything else.
struct HookSettingsEditor {
    /// Substring that identifies our hook commands.
    static let marker = "notchgate-hook"

    struct Registration {
        let event: HookEvent
        let matcher: String?
        let timeout: Int
        /// Background hook that can wake Claude later (exit code 2).
        var asyncRewake = false
    }

    static let registrations: [Registration] = [
        Registration(event: .permissionRequest, matcher: "*", timeout: 3600),
        // Blocks only for AskUserQuestion / ExitPlanMode; other tools are activity.
        Registration(event: .preToolUse, matcher: "*", timeout: 3600),
        Registration(event: .elicitation, matcher: nil, timeout: 3600),
        Registration(event: .stop, matcher: nil, timeout: 600),
        // Background twin of Stop: holds the "reply from the notch" composer
        // open for up to an hour without blocking Claude.
        Registration(event: .stop, matcher: nil, timeout: 3600, asyncRewake: true),
        Registration(event: .postToolUse, matcher: "*", timeout: 5),
        Registration(event: .notification, matcher: nil, timeout: 5),
        Registration(event: .userPromptSubmit, matcher: nil, timeout: 5),
        Registration(event: .sessionStart, matcher: nil, timeout: 5),
        Registration(event: .sessionEnd, matcher: nil, timeout: 5),
        Registration(event: .preCompact, matcher: nil, timeout: 5),
    ]

    let hookPath: String

    var command: String { "\"\(hookPath)\"" }

    // MARK: Queries

    func isInstalled(in settings: JSONValue) -> Bool {
        Self.registrations.allSatisfy { registration in
            groups(in: settings, for: registration.event).contains(where: Self.containsOurHook)
        }
    }

    /// True when any NotchGate entry exists (installed by any version).
    func hasAnyHook(in settings: JSONValue) -> Bool {
        (settings["hooks"]?.objectValue ?? [:]).values
            .flatMap { $0.arrayValue ?? [] }
            .contains(where: Self.containsOurHook)
    }

    /// True when our entries exactly match this version's registrations.
    func isCurrent(in settings: JSONValue) -> Bool {
        installing(into: settings) == settings
    }

    /// Other tools' `PermissionRequest` commands. They would race NotchGate
    /// to answer the same prompt, so setup warns about them.
    func conflictingCommands(in settings: JSONValue) -> [String] {
        groups(in: settings, for: .permissionRequest)
            .flatMap { $0["hooks"]?.arrayValue ?? [] }
            .filter { !Self.isOurHook($0) }
            .compactMap { $0["command"]?.stringValue }
    }

    // MARK: Mutations

    /// Idempotent: removes any previous NotchGate entries, then adds fresh ones.
    func installing(into settings: JSONValue) -> JSONValue {
        var hooks = uninstalling(from: settings)["hooks"]?.objectValue ?? [:]
        for registration in Self.registrations {
            var groups = hooks[registration.event.rawValue]?.arrayValue ?? []
            groups.append(group(for: registration))
            hooks[registration.event.rawValue] = .array(groups)
        }
        return settings.setting("hooks", to: .object(hooks))
    }

    /// Removes only NotchGate's hook commands, pruning containers left empty.
    func uninstalling(from settings: JSONValue) -> JSONValue {
        guard var hooks = settings["hooks"]?.objectValue else { return settings }

        for (event, value) in hooks {
            let groups = (value.arrayValue ?? []).compactMap { group -> JSONValue? in
                let remaining = (group["hooks"]?.arrayValue ?? []).filter { !Self.isOurHook($0) }
                return remaining.isEmpty ? nil : group.setting("hooks", to: .array(remaining))
            }
            hooks[event] = groups.isEmpty ? nil : .array(groups)
        }
        return settings.setting("hooks", to: .object(hooks))
    }

    // MARK: Helpers

    private func group(for registration: Registration) -> JSONValue {
        var hook: [String: JSONValue] = [
            "type": .string("command"),
            "command": .string(registration.asyncRewake ? command + " --rewake" : command),
            "timeout": .number(Double(registration.timeout)),
        ]
        if registration.asyncRewake { hook["asyncRewake"] = .bool(true) }
        var group: [String: JSONValue] = ["hooks": .array([.object(hook)])]
        if let matcher = registration.matcher { group["matcher"] = .string(matcher) }
        return .object(group)
    }

    private func groups(in settings: JSONValue, for event: HookEvent) -> [JSONValue] {
        settings["hooks"]?[event.rawValue]?.arrayValue ?? []
    }

    private static func containsOurHook(_ group: JSONValue) -> Bool {
        (group["hooks"]?.arrayValue ?? []).contains(where: isOurHook)
    }

    private static func isOurHook(_ hook: JSONValue) -> Bool {
        hook["command"]?.stringValue?.contains(marker) == true
    }
}
