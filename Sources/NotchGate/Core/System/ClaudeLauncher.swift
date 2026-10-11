import AppKit
import Foundation

/// Opens a new Terminal window that starts Claude Code, for when nothing is running yet.
///
/// Writes a `.command` script and hands it to Terminal, which needs no
/// Automation permission. The script runs in a login shell so `claude` resolves
/// the same way it does in a normal terminal.
enum ClaudeLauncher {
    private static let terminalBundleID = "com.apple.Terminal"
    private static let scriptName = "notchgate-start-claude.command"

    @MainActor
    @discardableResult
    static func openTerminalWithClaude() -> Bool {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID) else {
            return false
        }
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent(scriptName)
        do {
            try "#!/bin/zsh -l\nclaude\n".write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return false
        }
        NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        return true
    }
}
