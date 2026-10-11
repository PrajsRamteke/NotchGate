import AppKit
import Foundation

/// Opens a new Terminal window that starts Claude Code: a fresh session, or a
/// past one picked up with `claude --resume`.
///
/// Writes a `.command` script and hands it to Terminal, which needs no
/// Automation permission. The script runs the user's shell as an interactive
/// login shell (what a new Terminal tab does), so `claude` resolves from
/// `.zshrc` too — a plain `zsh -l` skips it and can find another install or none.
/// Each launch gets its own script, which deletes itself once Terminal runs it.
enum ClaudeLauncher {
    enum Mode: Equatable, Sendable {
        case new
        case resume(sessionID: String)
    }

    enum LaunchError: LocalizedError, Equatable {
        case terminalMissing
        case folderMissing(String)
        case invalidSessionID
        case scriptFailed(String)
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .terminalMissing: return "Terminal isn't installed."
            case .folderMissing(let path): return "\((path as NSString).abbreviatingWithTildeInPath) no longer exists."
            case .invalidSessionID: return "That session can't be resumed."
            case .scriptFailed(let reason): return "Couldn't prepare the launch: \(reason)"
            case .openFailed(let reason): return "Terminal didn't open: \(reason)"
            }
        }
    }

    private static let terminalBundleID = "com.apple.Terminal"

    /// Starts Claude Code in `directory` (Terminal's default folder when `nil`).
    /// `completion` reports a failure, or `nil` once Terminal has the script.
    @MainActor
    static func launch(
        _ mode: Mode,
        in directory: String? = nil,
        completion: @escaping @MainActor (LaunchError?) -> Void = { _ in }
    ) {
        do throws(LaunchError) {
            guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID) else {
                throw .terminalMissing
            }
            if let directory {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw .folderMissing(directory)
                }
            }
            let scriptURL = try writeScript(script(mode, in: directory))
            NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                let failure = error.map { LaunchError.openFailed($0.localizedDescription) }
                if failure != nil { try? FileManager.default.removeItem(at: scriptURL) }
                Task { @MainActor in completion(failure) }
            }
        } catch {
            Log.app.error("Claude launch failed: \(error.localizedDescription, privacy: .public)")
            completion(error)
        }
    }

    /// Opens a Terminal window running a fresh Claude Code, for when no session exists yet.
    @MainActor
    static func openTerminalWithClaude() {
        launch(.new)
    }

    /// The `.command` script's text. Pure, so the quoting can be unit-tested.
    static func script(_ mode: Mode, in directory: String?) throws(LaunchError) -> String {
        let command: String
        switch mode {
        case .new:
            command = "claude"
        case .resume(let sessionID):
            // Ids are UUIDs; anything else could smuggle shell syntax in.
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            guard !sessionID.isEmpty, sessionID.unicodeScalars.allSatisfy(allowed.contains) else {
                throw .invalidSessionID
            }
            command = "claude --resume \(sessionID)"
        }
        var lines = ["#!/bin/sh", "rm -f \"$0\""]
        if let directory {
            let quoted = shellQuoted(directory)
            lines.append("cd \(quoted) || { echo \"NotchGate: couldn't open \"\(quoted); exit 1; }")
        }
        lines.append("exec \"${SHELL:-/bin/zsh}\" -l -i -c \(shellQuoted(command))")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `text` as one single-quoted shell word.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func writeScript(_ text: String) throws(LaunchError) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchgate-claude-\(UUID().uuidString).command")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw .scriptFailed(error.localizedDescription)
        }
        return url
    }
}
