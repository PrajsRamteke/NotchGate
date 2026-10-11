import Foundation
import NotchGateKit

/// Pure transformations of `settings.json` that put NotchGate's status line
/// relay in place of the user's `statusLine` and back. The relay runs the
/// user's own command (saved separately), so their status line looks the same.
struct StatusLineSettingsEditor {
    static let flag = "--statusline"

    let hookPath: String

    var command: String { "\"\(hookPath)\" \(Self.flag)" }

    func isInstalled(in settings: JSONValue) -> Bool {
        Self.isRelay(settings["statusLine"])
    }

    /// Points `statusLine` at the relay, keeping `padding`, `refreshInterval`
    /// and any other fields the user set.
    ///
    /// - Parameter saved: the original kept from an earlier install, if any.
    /// - Returns: the new settings and the user's own status line to keep
    ///   (`nil` when they had none).
    func installing(into settings: JSONValue, keeping saved: JSONValue?) -> (settings: JSONValue, original: JSONValue?) {
        let current = settings["statusLine"]
        if let current, Self.isRelay(current) {
            // Already ours: only refresh the path in case the binary moved.
            return (settings.setting("statusLine", to: current.setting("command", to: .string(command))), saved)
        }
        let original = current?.objectValue == nil ? nil : current
        let relay = (original ?? .object([:]))
            .setting("type", to: .string("command"))
            .setting("command", to: .string(command))
        return (settings.setting("statusLine", to: relay), original)
    }

    /// Puts the user's command back (or removes `statusLine` if they had
    /// none). Leaves a status line the user has since replaced alone.
    func uninstalling(from settings: JSONValue, original: JSONValue?) -> JSONValue {
        guard let current = settings["statusLine"], Self.isRelay(current) else { return settings }
        guard let command = original?["command"] else { return settings.removing("statusLine") }
        return settings.setting("statusLine", to: current.setting("command", to: command))
    }

    private static func isRelay(_ statusLine: JSONValue?) -> Bool {
        guard let command = statusLine?["command"]?.stringValue else { return false }
        return command.contains(HookSettingsEditor.marker) && command.contains(flag)
    }
}

/// Installs the relay into `~/.claude/settings.json` and keeps the user's
/// original status line in `BridgeLocation.originalStatusLineURL`.
struct StatusLineInstaller {
    var settingsFile = ClaudeSettingsFile()
    var binary = HookBinary()
    var originalURL = BridgeLocation.originalStatusLineURL

    private var editor: StatusLineSettingsEditor { StatusLineSettingsEditor(hookPath: binary.installedURL.path) }

    var isInstalled: Bool {
        binary.isPresent && editor.isInstalled(in: (try? settingsFile.read()) ?? .object([:]))
    }

    func install() throws {
        try binary.installIfNeeded()
        let settings = try settingsFile.read()
        let result = editor.installing(into: settings, keeping: loadOriginal())
        // Saved before the settings change, so the relay never runs without it.
        try saveOriginal(result.original)
        if result.settings != settings { try settingsFile.write(result.settings) }
    }

    func uninstall() throws {
        let settings = try settingsFile.read()
        let restored = editor.uninstalling(from: settings, original: loadOriginal())
        if restored != settings { try settingsFile.write(restored) }
        try? FileManager.default.removeItem(at: originalURL)
    }

    private func loadOriginal() -> JSONValue? {
        guard let data = try? Data(contentsOf: originalURL) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func saveOriginal(_ original: JSONValue?) throws {
        guard let original else {
            try? FileManager.default.removeItem(at: originalURL)
            return
        }
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(original).write(to: originalURL, options: .atomic)
    }
}
