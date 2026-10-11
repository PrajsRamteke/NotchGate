import AppKit
import Foundation

/// Opens a new Terminal window that starts Claude Code, for when nothing is running yet.
///
/// Writes a `.command` script and hands it to Terminal, which needs no
/// Automation permission. The script runs the user's shell as an interactive
/// login shell (what a new Terminal tab does), so `claude` resolves from
/// `.zshrc` too — a plain `zsh -l` skips it and can find another install or none.
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
            try "#!/bin/sh\nexec \"${SHELL:-/bin/zsh}\" -l -i -c claude\n".write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            return false
        }
        NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        return true
    }
}
