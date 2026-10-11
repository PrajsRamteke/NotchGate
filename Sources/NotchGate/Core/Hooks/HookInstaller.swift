import Foundation
import NotchGateKit
import Observation

/// Installs the hook binary and wires it into `~/.claude/settings.json`.
///
/// Every write is preceded by a timestamped backup of the settings file.
@MainActor
@Observable
final class HookInstaller {
    enum Status: Equatable {
        case installed
        case notInstalled
        case failed(String)
    }

    private(set) var status: Status = .notInstalled

    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let settingsURL: URL
    @ObservationIgnored private let installedHookURL: URL
    @ObservationIgnored private var editor: HookSettingsEditor { HookSettingsEditor(hookPath: installedHookURL.path) }

    init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
        installedHookURL: URL = BridgeLocation.installedHookURL
    ) {
        self.settingsURL = settingsURL
        self.installedHookURL = installedHookURL
        refresh()
    }

    /// Other tools' permission hooks currently registered (see `HookSettingsEditor`).
    var conflictingCommands: [String] {
        editor.conflictingCommands(in: (try? readSettings()) ?? .object([:]))
    }

    func refresh() {
        let binaryPresent = fileManager.isExecutableFile(atPath: installedHookURL.path)
        let settings = (try? readSettings()) ?? .object([:])
        status = (binaryPresent && editor.isInstalled(in: settings)) ? .installed : .notInstalled
    }

    /// Re-installs when an older NotchGate set up different hooks or shipped
    /// a different hook binary. Never installs where the user hasn't opted in.
    func upgradeIfNeeded() {
        guard let settings = try? readSettings(), editor.hasAnyHook(in: settings) else { return }
        let binaryCurrent = Self.bundledHookURL.map {
            fileManager.contentsEqual(atPath: $0.path, andPath: installedHookURL.path)
        } ?? true
        guard !editor.isCurrent(in: settings) || !binaryCurrent else { return }
        Log.hooks.info("Upgrading hooks to this version")
        install()
    }

    func install() {
        perform {
            try installBinary()
            try writeSettings(editor.installing(into: readSettings()))
            Log.hooks.info("Hooks installed")
        }
    }

    func uninstall() {
        perform {
            try writeSettings(editor.uninstalling(from: readSettings()))
            Log.hooks.info("Hooks removed")
        }
    }

    // MARK: Private

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            refresh()
        } catch {
            Log.hooks.error("Hook operation failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    private func installBinary() throws {
        guard let source = Self.bundledHookURL, fileManager.fileExists(atPath: source.path) else {
            throw InstallError.hookBinaryMissing
        }
        try fileManager.createDirectory(
            at: installedHookURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: installedHookURL.path) {
            try fileManager.removeItem(at: installedHookURL)
        }
        try fileManager.copyItem(at: source, to: installedHookURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHookURL.path)
    }

    /// The hook ships next to the app executable (both in `swift build`
    /// output and in `NotchGate.app/Contents/MacOS`).
    private static var bundledHookURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("notchgate-hook")
    }

    private func readSettings() throws -> JSONValue {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return .object([:]) }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return .object([:]) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func writeSettings(_ settings: JSONValue) throws {
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: settingsURL.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = settingsURL.appendingPathExtension("notchgate-\(stamp).bak")
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }

    enum InstallError: LocalizedError {
        case hookBinaryMissing

        var errorDescription: String? {
            "The notchgate-hook binary was not found next to the app."
        }
    }
}
