import Foundation

/// Where a Claude Code session's terminal lives, and how to type into it.
enum TerminalHost: Equatable, Sendable {
    /// A tmux pane (inside any terminal app).
    case tmux(socket: String, pane: String, searchPath: String?)
    case iTerm(sessionID: String?, tty: String?)
    case appleTerminal(tty: String)
    /// VS Code family integrated terminal, reached through the NotchGate Bridge extension.
    case editor(name: String, bundleID: String?, processIDs: [Int32])
    case wezTerm(pane: String, socket: String?, searchPath: String?)
    case unsupported(name: String)

    var displayName: String {
        switch self {
        case .tmux: return "tmux"
        case .iTerm: return "iTerm"
        case .appleTerminal: return "Terminal"
        case .editor(let name, _, _): return name
        case .wezTerm: return "WezTerm"
        case .unsupported(let name): return name
        }
    }

    var isSupported: Bool {
        if case .unsupported = self { return false }
        return true
    }
}

/// Figures out a session's `TerminalHost` from the Claude process's
/// environment (most precise) and its process lineage (fallback).
enum TerminalHostDetector {
    static let editorNames: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.exafunction.windsurf": "Windsurf",
        "com.vscodium": "VSCodium",
    ]

    static func detect(claudePID: Int32) -> TerminalHost {
        let lineage = ProcessInspector.lineage(of: claudePID)
        let environment = ProcessInspector.environment(of: claudePID) ?? [:]
        return host(environment: environment, lineage: lineage)
    }

    /// Pure decision logic, kept separate so it can be unit-tested.
    static func host(environment env: [String: String], lineage: [ProcessRecord]) -> TerminalHost {
        let tty = lineage.first?.tty
        let searchPath = env["PATH"]

        // tmux wins: it can sit inside any other terminal.
        if let tmux = env["TMUX"], let pane = env["TMUX_PANE"], let socket = tmux.split(separator: ",").first {
            return .tmux(socket: String(socket), pane: pane, searchPath: searchPath)
        }

        let program = env["TERM_PROGRAM"] ?? ""
        let bundleID = env["__CFBundleIdentifier"]

        if program == "vscode" || bundleID.map({ editorNames[$0] != nil }) == true {
            let name = bundleID.flatMap { editorNames[$0] } ?? "VS Code"
            return .editor(name: name, bundleID: bundleID, processIDs: lineage.map(\.pid))
        }
        if program == "iTerm.app" || bundleID == "com.googlecode.iterm2" {
            // ITERM_SESSION_ID looks like "w0t1p0:6A1B…"; AppleScript's `id` is the part after ":".
            let sessionID = env["ITERM_SESSION_ID"]?.split(separator: ":").last.map(String.init)
            return .iTerm(sessionID: sessionID, tty: tty)
        }
        if program == "Apple_Terminal" || bundleID == "com.apple.Terminal", let tty {
            return .appleTerminal(tty: tty)
        }
        if program == "WezTerm", let pane = env["WEZTERM_PANE"] {
            return .wezTerm(pane: pane, socket: env["WEZTERM_UNIX_SOCKET"], searchPath: searchPath)
        }
        return .unsupported(name: program.isEmpty ? "this terminal" : program)
    }
}
