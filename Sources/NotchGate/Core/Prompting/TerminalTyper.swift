import AppKit
import Foundation

/// Types a prompt into a session's terminal, then presses Return, exactly as
/// if the user had typed it, so Claude Code records a real user prompt.
enum TerminalTyper {
    /// Presses Return alone, for a prompt that was typed but never submitted.
    static func pressReturn(into host: TerminalHost) async throws(PromptDeliveryError) {
        switch host {
        case .tmux(let socket, let pane, let searchPath):
            try await tmuxSession(socket: socket, pane: pane, searchPath: searchPath).sendReturn()
        case .iTerm(let sessionID, let tty):
            try await AppleScriptTyper.returnInITerm(sessionID: sessionID, tty: tty)
        case .appleTerminal(let tty):
            try await AppleScriptTyper.returnInTerminal(tty: tty)
        case .editor(let name, _, let processIDs):
            try await EditorBridgeTyper.pressReturn(editor: name, processIDs: processIDs)
        case .wezTerm(let pane, let socket, let searchPath):
            try await wezTermSession(pane: pane, socket: socket, searchPath: searchPath).send(PromptPayload.submitKey, asPaste: false)
        case .unsupported(let name):
            throw .unsupportedTerminal(name)
        }
    }

    static func type(_ payload: PromptPayload, into host: TerminalHost) async throws(PromptDeliveryError) {
        switch host {
        case .tmux(let socket, let pane, let searchPath):
            try await typeIntoTmux(payload, socket: socket, pane: pane, searchPath: searchPath)
        case .iTerm(let sessionID, let tty):
            try await AppleScriptTyper.typeIntoITerm(payload, sessionID: sessionID, tty: tty)
        case .appleTerminal(let tty):
            try await AppleScriptTyper.typeIntoTerminal(payload, tty: tty)
        case .editor(let name, _, let processIDs):
            try await EditorBridgeTyper.type(payload, editor: name, processIDs: processIDs)
        case .wezTerm(let pane, let socket, let searchPath):
            try await typeIntoWezTerm(payload, pane: pane, socket: socket, searchPath: searchPath)
        case .unsupported(let name):
            throw .unsupportedTerminal(name)
        }
    }

    // MARK: tmux

    private struct TmuxSession {
        let tmux: String
        let socket: String
        let pane: String

        func run(_ arguments: [String], stdin: String? = nil) async throws(PromptDeliveryError) {
            let output = try await CommandRunner.run(tmux, ["-S", socket] + arguments, stdin: stdin)
            guard output.succeeded else { throw .commandFailed(output.stderr.trimmed(or: "tmux exited with \(output.status)")) }
        }

        func sendReturn() async throws(PromptDeliveryError) {
            try await run(["send-keys", "-t", pane, "Enter"])
        }
    }

    private static func tmuxSession(socket: String, pane: String, searchPath: String?) async throws(PromptDeliveryError) -> TmuxSession {
        guard let tmux = CommandRunner.locate("tmux", searchPath: searchPath) else { throw .toolMissing("tmux") }
        let probe = try await CommandRunner.run(tmux, ["-S", socket, "display-message", "-p", "-t", pane, "#{pane_id}"])
        guard probe.succeeded else { throw .targetNotFound("tmux pane") }
        return TmuxSession(tmux: tmux, socket: socket, pane: pane)
    }

    private static func typeIntoTmux(
        _ payload: PromptPayload, socket: String, pane: String, searchPath: String?
    ) async throws(PromptDeliveryError) {
        let session = try await tmuxSession(socket: socket, pane: pane, searchPath: searchPath)
        if payload.isPasted {
            // paste-buffer -p wraps in bracketed paste because Claude Code asks for it.
            try await session.run(["load-buffer", "-b", "notchgate", "-"], stdin: payload.text)
            try await session.run(["paste-buffer", "-p", "-d", "-b", "notchgate", "-t", pane])
        } else {
            try await session.run(["send-keys", "-t", pane, "-l", "--", payload.text])
        }
        try? await Task.sleep(for: payload.submitDelay)
        try await session.sendReturn()
    }

    // MARK: WezTerm

    private struct WezTermSession {
        let wezterm: String
        let pane: String
        let environment: [String: String]

        func send(_ text: String, asPaste: Bool) async throws(PromptDeliveryError) {
            var arguments = ["cli", "send-text", "--pane-id", pane]
            if !asPaste { arguments.append("--no-paste") }
            let output = try await CommandRunner.run(wezterm, arguments + ["--", text], environment: environment)
            guard output.succeeded else { throw .commandFailed(output.stderr.trimmed(or: "wezterm exited with \(output.status)")) }
        }
    }

    private static func wezTermSession(pane: String, socket: String?, searchPath: String?) throws(PromptDeliveryError) -> WezTermSession {
        guard let wezterm = CommandRunner.locate(
            "wezterm", searchPath: searchPath, extra: ["/Applications/WezTerm.app/Contents/MacOS"]
        ) else { throw .toolMissing("wezterm") }
        return WezTermSession(wezterm: wezterm, pane: pane, environment: socket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:])
    }

    private static func typeIntoWezTerm(
        _ payload: PromptPayload, pane: String, socket: String?, searchPath: String?
    ) async throws(PromptDeliveryError) {
        let session = try wezTermSession(pane: pane, socket: socket, searchPath: searchPath)
        try await session.send(payload.text, asPaste: payload.isPasted)
        try? await Task.sleep(for: payload.submitDelay)
        try await session.send(PromptPayload.submitKey, asPaste: false)
    }
}

extension String {
    func trimmed(or fallback: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
