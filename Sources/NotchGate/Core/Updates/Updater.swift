import AppKit
import Foundation

/// Installs the latest NotchGate by running the same one-line installer as
/// the README, in the background. The installer downloads the prebuilt app
/// (building from source only if that's unavailable), swaps it in (quitting
/// this process) at the very end, then relaunches it.
enum Updater {
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchGate/update.log")
    }

    /// Problems that would make the update fail before it starts. The prebuilt
    /// download needs only curl; if the installer has to build from source
    /// instead, it reports missing developer tools in the log itself.
    static func preflight() async -> String? {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") ? nil : "Updating needs curl, which is missing."
    }

    /// Starts the installer. `onExit` runs only if this app is still alive
    /// afterwards, which means the update failed before the swap.
    static func start(onExit: @escaping @MainActor (Int32) -> Void) throws {
        let log = try openLog()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "set -o pipefail; curl -fsSL '\(UpdateSource.installerURL)' | bash"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status) } }
        }
        try process.run()
        Log.app.info("Update started; log at \(logURL.path, privacy: .public)")
    }

    static func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    /// Quits and reopens the app from its (now replaced) bundle. Used when the
    /// installer succeeded but couldn't quit us, e.g. an older installer whose
    /// `pkill` skipped this process because it is the installer's ancestor.
    @MainActor
    static func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this process to exit, so `open` launches the new build instead of re-activating us.
        reopen.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
        do {
            try reopen.run()
            NSApp.terminate(nil)
        } catch {
            Log.app.error("Relaunch after update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func openLog() throws -> FileHandle {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: Data("NotchGate update — \(Date())\n".utf8))
        let handle = try FileHandle(forWritingTo: logURL)
        // Append after the header; a fresh handle starts at offset 0 and the installer would overwrite it.
        try handle.seekToEnd()
        return handle
    }
}
