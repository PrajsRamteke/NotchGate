import Foundation
import NotchGateKit

/// Reads and writes Claude Code's `~/.claude/settings.json`. Every write is
/// preceded by a timestamped backup next to it.
struct ClaudeSettingsFile {
    var url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    private var fileManager: FileManager { .default }

    func read() throws -> JSONValue {
        guard fileManager.fileExists(atPath: url.path) else { return .object([:]) }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return .object([:]) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func write(_ settings: JSONValue) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.appendingPathExtension("notchgate-\(stamp).bak")
            // Two writes in the same second (hooks, then the status line) share one backup.
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: url, to: backup)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}

/// The `notchgate-hook` binary Claude Code runs, copied to a stable path so
/// settings keep working when the app moves or updates.
struct HookBinary {
    var installedURL: URL = BridgeLocation.installedHookURL

    private var fileManager: FileManager { .default }

    /// The hook ships next to the app executable (both in `swift build`
    /// output and in `NotchGate.app/Contents/MacOS`).
    static var bundledURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("notchgate-hook")
    }

    var isPresent: Bool { fileManager.isExecutableFile(atPath: installedURL.path) }

    /// True when the installed copy matches the one shipped with this app.
    var isCurrent: Bool {
        guard let source = Self.bundledURL, fileManager.fileExists(atPath: source.path) else { return true }
        return fileManager.contentsEqual(atPath: source.path, andPath: installedURL.path)
    }

    func install() throws {
        guard let source = Self.bundledURL, fileManager.fileExists(atPath: source.path) else {
            throw InstallError.hookBinaryMissing
        }
        try fileManager.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: installedURL.path) {
            try fileManager.removeItem(at: installedURL)
        }
        try fileManager.copyItem(at: source, to: installedURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
    }

    func installIfNeeded() throws {
        if !isPresent || !isCurrent { try install() }
    }

    enum InstallError: LocalizedError {
        case hookBinaryMissing

        var errorDescription: String? {
            "The notchgate-hook binary was not found next to the app."
        }
    }
}
