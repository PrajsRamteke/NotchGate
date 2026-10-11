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

    @ObservationIgnored private let settingsFile: ClaudeSettingsFile
    @ObservationIgnored private let binary: HookBinary
    @ObservationIgnored private var editor: HookSettingsEditor { HookSettingsEditor(hookPath: binary.installedURL.path) }

    init(
        settingsURL: URL = ClaudeSettingsFile().url,
        installedHookURL: URL = BridgeLocation.installedHookURL
    ) {
        settingsFile = ClaudeSettingsFile(url: settingsURL)
        binary = HookBinary(installedURL: installedHookURL)
        refresh()
    }

    /// Other tools' permission hooks currently registered (see `HookSettingsEditor`).
    var conflictingCommands: [String] {
        editor.conflictingCommands(in: (try? settingsFile.read()) ?? .object([:]))
    }

    func refresh() {
        let settings = (try? settingsFile.read()) ?? .object([:])
        status = (binary.isPresent && editor.isInstalled(in: settings)) ? .installed : .notInstalled
    }

    /// Re-installs when an older NotchGate set up different hooks or shipped
    /// a different hook binary. Never installs where the user hasn't opted in.
    func upgradeIfNeeded() {
        guard let settings = try? settingsFile.read(), editor.hasAnyHook(in: settings) else { return }
        guard !editor.isCurrent(in: settings) || !binary.isCurrent else { return }
        Log.hooks.info("Upgrading hooks to this version")
        install()
    }

    func install() {
        perform {
            try binary.install()
            try settingsFile.write(editor.installing(into: settingsFile.read()))
            Log.hooks.info("Hooks installed")
        }
    }

    func uninstall() {
        perform {
            try settingsFile.write(editor.uninstalling(from: settingsFile.read()))
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
}
