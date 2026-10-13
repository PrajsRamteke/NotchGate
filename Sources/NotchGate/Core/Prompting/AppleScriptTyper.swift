import AppKit
import Foundation

/// Types into iTerm2 and Terminal.app sessions via AppleScript, targeting the
/// exact session/tab (by iTerm session id or tty) without stealing focus.
///
/// Scripts run through `osascript` with the prompt passed as an argument, so
/// no user text is ever spliced into script source.
enum AppleScriptTyper {
    static let iTermBundleID = "com.googlecode.iterm2"
    static let terminalBundleID = "com.apple.Terminal"

    /// macOS asks for Automation permission the first time; leave time to click Allow.
    private static let timeout: TimeInterval = 90

    static func typeIntoITerm(_ payload: PromptPayload, sessionID: String?, tty: String?) async throws(PromptDeliveryError) {
        try await run(iTermScript, app: "iTerm", bundleID: iTermBundleID,
                      arguments: [sessionID ?? "", tty ?? "", payload.typedText, String(payload.submitDelayMilliseconds)])
    }

    static func typeIntoTerminal(_ payload: PromptPayload, tty: String) async throws(PromptDeliveryError) {
        try await run(terminalScript, app: "Terminal", bundleID: terminalBundleID,
                      arguments: [tty, payload.typedText, String(payload.submitDelayMilliseconds)])
    }

    /// Presses Return alone (the scripts skip the text when it's empty).
    static func returnInITerm(sessionID: String?, tty: String?) async throws(PromptDeliveryError) {
        try await run(iTermScript, app: "iTerm", bundleID: iTermBundleID, arguments: [sessionID ?? "", tty ?? "", "", "0"])
    }

    static func returnInTerminal(tty: String) async throws(PromptDeliveryError) {
        try await run(terminalScript, app: "Terminal", bundleID: terminalBundleID, arguments: [tty, "", "0"])
    }

    private static func run(_ script: String, app: String, bundleID: String, arguments: [String]) async throws(PromptDeliveryError) {
        // `tell application` would launch a closed app; never do that.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            throw .appNotRunning(app)
        }
        let output = try await CommandRunner.run(
            "/usr/bin/osascript", ["-e", script] + arguments, timeout: timeout
        )
        let result = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.succeeded, result == "ok" { return }
        if result == "not-found" { throw .targetNotFound("\(app) tab") }
        throw mapError(output.stderr, app: app)
    }

    /// Translates AppleScript error numbers into friendly errors.
    static func mapError(_ stderr: String, app: String) -> PromptDeliveryError {
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") {
            return .automationDenied(app: app)
        }
        if stderr.contains("-600") { return .appNotRunning(app) }
        if stderr.contains("-1712") { return .timedOut(app) }
        return .commandFailed(stderr.trimmed(or: "\(app) didn't accept the text"))
    }

    // Return is sent separately after a pause so Claude Code treats it as a key press.
    // An empty payload skips the text and just presses Return.
    private static let iTermScript = """
    on run argv
        set targetID to item 1 of argv
        set targetTTY to item 2 of argv
        set payload to item 3 of argv
        set pause to (item 4 of argv as integer) / 1000
        tell application id "com.googlecode.iterm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if (targetID is not "" and (id of aSession as text) is targetID) or (targetTTY is not "" and (tty of aSession as text) is targetTTY) then
                            if payload is not "" then
                                tell aSession to write text payload newline no
                                delay pause
                            end if
                            tell aSession to write text (character id 13) newline no
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not-found"
    end run
    """

    // `do script` always appends Return. A second, empty `do script` makes sure
    // the prompt submits even if the first Return arrived inside the text
    // (an empty Return in Claude Code does nothing). An empty payload skips the
    // text and just presses Return.
    private static let terminalScript = """
    on run argv
        set targetTTY to item 1 of argv
        set payload to item 2 of argv
        set pause to (item 3 of argv as integer) / 1000
        tell application id "com.apple.Terminal"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    if (tty of aTab as text) is targetTTY then
                        if payload is not "" then
                            do script payload in aTab
                            delay pause
                        end if
                        do script "" in aTab
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "not-found"
    end run
    """
}
