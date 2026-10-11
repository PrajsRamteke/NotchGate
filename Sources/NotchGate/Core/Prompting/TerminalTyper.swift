import AppKit
import Foundation

/// Types a prompt into a session's terminal, then presses Return, exactly as
/// if the user had typed it, so Claude Code records a real user prompt.
enum TerminalTyper {
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

    private static func typeIntoTmux(
        _ payload: PromptPayload, socket: String, pane: String, searchPath: String?
    ) async throws(PromptDeliveryError) {
        guard let tmux = CommandRunner.locate("tmux", searchPath: searchPath) else { throw .toolMissing("tmux") }
        let server = ["-S", socket]

        func tmuxRun(_ arguments: [String], stdin: String? = nil) async throws(PromptDeliveryError) {
            let output = try await CommandRunner.run(tmux, server + arguments, stdin: stdin)
            guard output.succeeded else { throw .commandFailed(output.stderr.trimmed(or: "tmux exited with \(output.status)")) }
        }

        let probe = try await CommandRunner.run(tmux, server + ["display-message", "-p", "-t", pane, "#{pane_id}"])
        guard probe.succeeded else { throw .targetNotFound("tmux pane") }

        if payload.isPasted {
            // paste-buffer -p wraps in bracketed paste because Claude Code asks for it.
            try await tmuxRun(["load-buffer", "-b", "notchgate", "-"], stdin: payload.text)
            try await tmuxRun(["paste-buffer", "-p", "-d", "-b", "notchgate", "-t", pane])
        } else {
            try await tmuxRun(["send-keys", "-t", pane, "-l", "--", payload.text])
        }
        try? await Task.sleep(for: PromptPayload.submitDelay)
        try await tmuxRun(["send-keys", "-t", pane, "Enter"])
    }

    // MARK: WezTerm

    private static func typeIntoWezTerm(
        _ payload: PromptPayload, pane: String, socket: String?, searchPath: String?
    ) async throws(PromptDeliveryError) {
        guard let wezterm = CommandRunner.locate(
            "wezterm", searchPath: searchPath, extra: ["/Applications/WezTerm.app/Contents/MacOS"]
        ) else { throw .toolMissing("wezterm") }
        let environment = socket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]

        func send(_ text: String, asPaste: Bool) async throws(PromptDeliveryError) {
            var arguments = ["cli", "send-text", "--pane-id", pane]
            if !asPaste { arguments.append("--no-paste") }
            let output = try await CommandRunner.run(wezterm, arguments + ["--", text], environment: environment)
            guard output.succeeded else { throw .commandFailed(output.stderr.trimmed(or: "wezterm exited with \(output.status)")) }
        }

        try await send(payload.text, asPaste: payload.isPasted)
        try? await Task.sleep(for: PromptPayload.submitDelay)
        try await send(PromptPayload.submitKey, asPaste: false)
    }
}

extension String {
    func trimmed(or fallback: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
