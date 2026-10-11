import Dispatch
import Foundation
import NotchGateKit

/// `notchgate-hook --statusline`: Claude Code's status line command while a
/// status line widget is on. It saves the plan limits and the session's
/// details from the status line input for the app, then hands the same input
/// to the user's own status line command so their status line looks exactly as before.
struct StatusLineRelay {
    func run() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try? JSONDecoder().decode(JSONValue.self, from: input)

        if let payload, let snapshot = UsageSnapshot(statusLine: payload) {
            try? snapshot.save()
        }
        if let payload {
            // The branch where Claude is working now, which may be a worktree of the project.
            let workingDirectory = payload["workspace"]?["current_dir"]?.stringValue
                ?? payload["cwd"]?.stringValue
                ?? SessionSnapshot.directory(in: payload)
            let branch = workingDirectory.flatMap(GitBranch.current(in:))
            try? SessionSnapshot(statusLine: payload, branch: branch)?.save()
        }

        if let command = Self.originalCommand() {
            return runOriginal(command, input: input)
        }
        print(Self.fallbackLine(payload))
        return 0
    }

    /// The user's own status line command, saved when the relay took its place.
    private static func originalCommand() -> String? {
        guard let data = try? Data(contentsOf: BridgeLocation.originalStatusLineURL),
              let original = try? JSONDecoder().decode(JSONValue.self, from: data),
              let command = original["command"]?.stringValue,
              !command.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return command
    }

    /// Runs it the way Claude Code does (`/bin/sh -c`), sharing our stdout and
    /// stderr. Claude Code cancels a status line that's been overtaken by a
    /// newer update; pass that on so the user's script doesn't linger.
    private func runOriginal(_ command: String, input: Data) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        process.standardInput = stdin

        let cancellations = [SIGTERM, SIGINT, SIGHUP].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                if process.isRunning { process.terminate() }
                exit(128 + signalNumber)
            }
            source.resume()
            return source
        }
        defer { cancellations.forEach { $0.cancel() } }

        do {
            try process.run()
        } catch {
            return 1
        }
        // The script may exit without reading everything; ignore the broken pipe.
        signal(SIGPIPE, SIG_IGN)
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// For users who had no status line: the model and plan limits, so the row
    /// Claude Code reserves for the status line isn't blank.
    static func fallbackLine(_ payload: JSONValue?) -> String {
        var parts: [String] = []
        if let model = payload?["model"]?["display_name"]?.stringValue { parts.append(model) }
        let limits = payload?["rate_limits"]
        if let fiveHour = limits?["five_hour"]?["used_percentage"]?.doubleValue {
            parts.append("5h \(Int(fiveHour.rounded()))%")
        }
        if let week = limits?["seven_day"]?["used_percentage"]?.doubleValue {
            parts.append("week \(Int(week.rounded()))%")
        }
        return parts.joined(separator: " · ")
    }
}
