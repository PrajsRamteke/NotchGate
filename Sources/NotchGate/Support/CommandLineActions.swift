import AppKit
import Foundation

/// Headless entry points so setup can be scripted:
///
///     NotchGate --setup                   hooks + editor helper + launch at login
///     NotchGate --uninstall               remove hooks + disable launch at login
///     NotchGate --send-prompt PID TEXT    type a prompt into a Claude session (diagnostics)
///     NotchGate --snapshot DIR            render every card to PNG
@MainActor
enum CommandLineActions {
    /// Starts a requested action. Returns `true` if one was found; the action
    /// terminates the app itself when it's done.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if SnapshotRenderer.runIfRequested() { return finish(true) }
        if arguments.contains("--setup") { return runAsync(setUp) }
        if arguments.contains("--uninstall") { return finish(tearDown()) }
        if let flag = arguments.firstIndex(of: "--send-prompt"), arguments.count > flag + 2,
           let pid = Int32(arguments[flag + 1]) {
            let text = arguments[(flag + 2)...].joined(separator: " ")
            return runAsync { await sendPrompt(text, to: pid) }
        }
        return false
    }

    // MARK: Actions

    private static func setUp() async -> Bool {
        let installer = HookInstaller()
        installer.install()
        guard installer.status == .installed else {
            report("✗ Hook installation failed: \(installer.status)")
            return false
        }
        report("✓ Hooks installed → ~/.claude/settings.json (backup saved alongside)")
        for command in installer.conflictingCommands {
            report("⚠ Another PermissionRequest hook may race NotchGate: \(command)")
            report("  Remove it from ~/.claude/settings.json if prompts behave oddly.")
        }

        await installEditorHelper()

        guard LaunchAtLogin.isAvailable else {
            report("• Launch at login skipped (run from NotchGate.app to enable)")
            return true
        }
        LaunchAtLogin.setEnabled(true)
        report(LaunchAtLogin.isEnabled ? "✓ Launch at login enabled" : "• Launch at login needs approval in System Settings → Login Items")
        return true
    }

    /// Lets the notch type prompts into Cursor / VS Code terminals. Optional:
    /// failures are reported but never fail setup.
    private static func installEditorHelper() async {
        let helper = EditorHelperInstaller()
        guard !helper.editors.isEmpty else {
            report("• No VS Code-family editor found; skipped the editor helper")
            return
        }
        for (editor, succeeded) in await helper.install().sorted(by: { $0.key < $1.key }) {
            report(succeeded ? "✓ Editor helper installed in \(editor)" : "⚠ Editor helper failed in \(editor)")
        }
        if let error = helper.lastError { report("  \(error)") }
    }

    private static func tearDown() -> Bool {
        let installer = HookInstaller()
        installer.uninstall()
        LaunchAtLogin.setEnabled(false)
        report(installer.status == .notInstalled ? "✓ Hooks removed" : "✗ Removal failed: \(installer.status)")
        return installer.status == .notInstalled
    }

    /// Same code path as the notch's composer, for troubleshooting from a shell.
    private static func sendPrompt(_ text: String, to pid: Int32) async -> Bool {
        let host = TerminalHostDetector.detect(claudePID: pid)
        report("• Session \(pid) runs in: \(host.displayName)")
        do {
            let typed = try await PromptDispatcher().type(text, into: PromptTarget(sessionID: "", claudePID: pid, projectName: ""))
            report("✓ Typed into \(typed.displayName)")
            return true
        } catch {
            report("✗ \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Plumbing

    private static func runAsync(_ action: @escaping @MainActor () async -> Bool) -> Bool {
        Task { @MainActor in
            let succeeded = await action()
            exit(succeeded ? 0 : 1)
        }
        return true
    }

    private static func finish(_ succeeded: Bool) -> Bool {
        exit(succeeded ? 0 : 1)
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
