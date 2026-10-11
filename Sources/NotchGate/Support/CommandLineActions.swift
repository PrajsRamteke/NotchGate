import Foundation

/// Headless entry points so setup can be scripted:
///
///     NotchGate --setup        install hooks + enable launch at login
///     NotchGate --uninstall    remove hooks + disable launch at login
///     NotchGate --snapshot DIR render every card to PNG
@MainActor
enum CommandLineActions {
    /// Runs a requested action. Returns `true` when the app should exit afterwards.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if SnapshotRenderer.runIfRequested() { return true }
        if arguments.contains("--setup") { return finish(setUp()) }
        if arguments.contains("--uninstall") { return finish(tearDown()) }
        return false
    }

    private static func setUp() -> Bool {
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

        guard LaunchAtLogin.isAvailable else {
            report("• Launch at login skipped (run from NotchGate.app to enable)")
            return true
        }
        LaunchAtLogin.setEnabled(true)
        report(LaunchAtLogin.isEnabled ? "✓ Launch at login enabled" : "• Launch at login needs approval in System Settings → Login Items")
        return true
    }

    private static func tearDown() -> Bool {
        let installer = HookInstaller()
        installer.uninstall()
        LaunchAtLogin.setEnabled(false)
        report(installer.status == .notInstalled ? "✓ Hooks removed" : "✗ Removal failed: \(installer.status)")
        return installer.status == .notInstalled
    }

    private static func finish(_ succeeded: Bool) -> Bool {
        if !succeeded { exit(1) }
        return true
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
