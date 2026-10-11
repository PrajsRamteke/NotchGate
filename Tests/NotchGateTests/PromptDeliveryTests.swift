import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Prompt delivery")
struct PromptDeliveryTests {
    // MARK: Payload

    @Test func singleLinePromptsAreTypedAsIs() throws {
        let payload = try PromptPayload("  fix the login bug  ")
        #expect(payload.text == "fix the login bug")
        #expect(!payload.isMultiline)
        #expect(payload.typedText == "fix the login bug")
    }

    @Test func multiLinePromptsUseBracketedPaste() throws {
        let payload = try PromptPayload("first\r\nsecond")
        #expect(payload.text == "first\nsecond")
        #expect(payload.typedText == "\u{1B}[200~first\nsecond\u{1B}[201~")
    }

    @Test func controlCharactersCannotReachTheTerminal() throws {
        let payload = try PromptPayload("hi \u{1B}[31mred\u{07}\u{9B} \"quotes\" `ticks` 🚀")
        #expect(payload.text == "hi [31mred \"quotes\" `ticks` 🚀")
        #expect(!payload.text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" && $0 != "\t" })
    }

    @Test func emptyAndOversizedPromptsAreRejected() {
        #expect(throws: PromptDeliveryError.emptyPrompt) { try PromptPayload(" \u{1B}\u{01} \n ") }
        #expect(throws: PromptDeliveryError.tooLong(limit: PromptPayload.maxLength)) {
            try PromptPayload(String(repeating: "x", count: PromptPayload.maxLength + 1))
        }
    }

    // MARK: Process environment

    @Test func parsesProcArgsLayout() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(2)) { bytes += $0 }
        for part in ["/usr/bin/claude", "", "", "claude", "--resume", "TERM_PROGRAM=tmux", "TMUX_PANE=%3", "EMPTY="] {
            bytes += Array(part.utf8) + [0]
        }
        bytes += [0]
        let env = ProcessInspector.parseProcArgs(bytes)
        #expect(env == ["TERM_PROGRAM": "tmux", "TMUX_PANE": "%3", "EMPTY": ""])
    }

    @Test func readsThisProcessEnvironment() throws {
        let env = try #require(ProcessInspector.environment(of: getpid()))
        #expect(env["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(ProcessInspector.lineage(of: getpid()).first?.pid == getpid())
    }

    // MARK: Terminal detection

    private let lineage = [ProcessRecord(pid: 50, parentPID: 40, name: "claude", tty: "/dev/ttys004"),
                           ProcessRecord(pid: 40, parentPID: 1, name: "zsh", tty: "/dev/ttys004")]

    @Test func tmuxWinsOverTheOuterTerminal() {
        let host = TerminalHostDetector.host(
            environment: ["TMUX": "/private/tmp/tmux-501/default,123,0", "TMUX_PANE": "%7", "TERM_PROGRAM": "tmux",
                          "__CFBundleIdentifier": "com.googlecode.iterm2"],
            lineage: lineage
        )
        #expect(host == .tmux(socket: "/private/tmp/tmux-501/default", pane: "%7", searchPath: nil))
    }

    @Test func detectsEditorsITermTerminalAndWezTerm() {
        #expect(TerminalHostDetector.host(
            environment: ["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"], lineage: lineage
        ) == .editor(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", processIDs: [50, 40]))
        #expect(TerminalHostDetector.host(
            environment: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t1p0:ABC-123"], lineage: lineage
        ) == .iTerm(sessionID: "ABC-123", tty: "/dev/ttys004"))
        #expect(TerminalHostDetector.host(
            environment: ["TERM_PROGRAM": "Apple_Terminal"], lineage: lineage
        ) == .appleTerminal(tty: "/dev/ttys004"))
        #expect(TerminalHostDetector.host(
            environment: ["TERM_PROGRAM": "WezTerm", "WEZTERM_PANE": "4"], lineage: lineage
        ) == .wezTerm(pane: "4", socket: nil, searchPath: nil))
        #expect(!TerminalHostDetector.host(environment: ["TERM_PROGRAM": "ghostty"], lineage: lineage).isSupported)
    }

    // MARK: Errors

    @Test func mapsAppleScriptErrors() {
        #expect(AppleScriptTyper.mapError("execution error: Not authorized to send Apple events to iTerm. (-1743)", app: "iTerm")
            == .automationDenied(app: "iTerm"))
        #expect(AppleScriptTyper.mapError("(-600)", app: "Terminal") == .appNotRunning("Terminal"))
        if case .commandFailed = AppleScriptTyper.mapError("something odd", app: "Terminal") {} else {
            Issue.record("Unknown errors should surface their message")
        }
    }

    @Test func everyErrorHasAUserFacingMessage() {
        let errors: [PromptDeliveryError] = [
            .emptyPrompt, .tooLong(limit: 10), .sessionEnded, .awaitingAnswer("Permission"),
            .unsupportedTerminal("Ghostty"), .automationDenied(app: "iTerm"), .appNotRunning("iTerm"),
            .targetNotFound("tmux pane"), .toolMissing("tmux"), .editorHelperMissing("Cursor"),
            .commandFailed("x"), .timedOut("osascript"),
        ]
        for error in errors { #expect(!(error.errorDescription ?? "").isEmpty) }
    }

    // MARK: Guarding dialogs

    @Test @MainActor func refusesToTypeWhileClaudeAwaitsAnAnswer() async {
        let store = RequestStore()
        let controller = ComposerController(store: store, activity: ActivityTracker())
        store.enqueue(ClaudeRequest(
            id: UUID(), event: .permissionRequest,
            session: SessionInfo(id: "s1", cwd: "/tmp", claudePID: getpid()),
            kind: .permission(ToolPermission(toolName: "Bash", input: .object([:]), suggestions: []))
        ), responder: DemoResponder())

        let outcome = await controller.send("hi", to: PromptTarget(sessionID: "s1", claudePID: getpid(), projectName: "x"))
        #expect(outcome == .failed(.awaitingAnswer("Permission"), fallback: nil))
    }
}
