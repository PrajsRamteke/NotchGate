import AppKit
import Darwin

/// Brings a Claude Code session's own terminal to the front, not just the app
/// hosting it (activating the app alone shows whichever window or tab was used
/// last, which is wrong as soon as several are open):
///
/// - Terminal, iTerm: the exact tab and pane, by tty or session ID (AppleScript).
/// - tmux: the session's window and pane, then the terminal running tmux.
/// - WezTerm: the session's pane.
/// - Cursor, VS Code, Windsurf, VSCodium: the window whose workspace holds the
///   session, even on another Space (see `EditorWindow`). No extension needed.
///
/// Anything that can't be pinpointed falls back to activating the app.
@MainActor
enum TerminalActivator {
    private static let maxDepth = 24

    static func activate(claudePID: Int32, cwd: String) {
        let host = TerminalHostDetector.detect(claudePID: claudePID)
        Task {
            if await focusSession(in: host) { return }
            activateApp(above: claudePID, showing: cwd)
        }
    }

    // MARK: Exact tab or pane

    /// `true` when the session's tab is selected and its app is in front.
    private static func focusSession(in host: TerminalHost) async -> Bool {
        switch host {
        case .appleTerminal(let tty):
            return (try? await AppleScriptTyper.focusTerminal(tty: tty)) != nil
        case .iTerm(let sessionID, let tty):
            return (try? await AppleScriptTyper.focusITerm(sessionID: sessionID, tty: tty)) != nil
        case .tmux(let socket, let pane, let searchPath):
            return await focusTmux(socket: socket, pane: pane, searchPath: searchPath)
        case .wezTerm(let pane, let socket, let searchPath):
            // Selects the pane and its tab; the app comes forward afterwards.
            if let wezterm = CommandRunner.locate("wezterm", searchPath: searchPath, extra: ["/Applications/WezTerm.app/Contents/MacOS"]) {
                _ = try? await CommandRunner.run(
                    wezterm, ["cli", "activate-pane", "--pane-id", pane],
                    environment: socket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]
                )
            }
            return false
        case .editor, .unsupported:
            return false
        }
    }

    /// Switches tmux to the session's window and pane, then brings forward the
    /// terminal showing tmux (Claude runs under the tmux server, not that terminal).
    private static func focusTmux(socket: String, pane: String, searchPath: String?) async -> Bool {
        guard let tmux = CommandRunner.locate("tmux", searchPath: searchPath) else { return false }
        _ = try? await CommandRunner.run(tmux, ["-S", socket, "select-window", "-t", pane])
        _ = try? await CommandRunner.run(tmux, ["-S", socket, "select-pane", "-t", pane])
        let clients = try? await CommandRunner.run(tmux, ["-S", socket, "list-clients", "-F", "#{client_pid}"])
        guard let clientPID = clients?.stdout.split(separator: "\n").first.flatMap({ Int32($0) }) else { return false }
        let outer = TerminalHostDetector.detect(claudePID: clientPID)
        if case .tmux = outer { return activateApp(above: clientPID, showing: nil) }
        if await focusSession(in: outer) { return true }
        return activateApp(above: clientPID, showing: nil)
    }

    // MARK: The app (and the project's window)

    /// Activates the first regular app above `pid`; for an editor, the window showing `cwd`.
    @discardableResult
    private static func activateApp(above pid: Int32, showing cwd: String?) -> Bool {
        guard let app = hostApp(above: pid) else { return false }
        if let cwd, EditorWindow.focus(app: app, showing: cwd) { return true }
        return app.activate()
    }

    private static func hostApp(above start: Int32) -> NSRunningApplication? {
        var pid = start
        for _ in 0..<maxDepth {
            guard pid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: pid), parent != pid else { break }
            pid = parent
        }
        return nil
    }

    private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
