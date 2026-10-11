import AppKit
import Foundation

/// Installs the latest NotchGate by running the same one-line installer as
/// the README, in the background. The installer builds first and only swaps
/// the app (quitting this process) at the very end, then relaunches it.
enum Updater {
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchGate/update.log")
    }

    /// Problems that would make the update fail before it starts.
    static func preflight() async -> String? {
        let tools = ["/usr/bin/curl", "/usr/bin/git", "/usr/bin/swift"]
        if let missing = tools.first(where: { !FileManager.default.isExecutableFile(atPath: $0) }) {
            return "Updating needs \(URL(fileURLWithPath: missing).lastPathComponent), which is missing."
        }
        let developerTools = try? await CommandRunner.run("/usr/bin/xcode-select", ["-p"])
        if developerTools?.succeeded != true {
            return "Updating builds NotchGate from source and needs Apple's Command Line Tools. Run `xcode-select --install`, then try again."
        }
        return nil
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

    private static func openLog() throws -> FileHandle {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: Data("NotchGate update — \(Date())\n".utf8))
        return try FileHandle(forWritingTo: logURL)
    }
}
