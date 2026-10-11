import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService`. Only works when running from an `.app`
/// bundle; under `swift run` it reports itself as unavailable.
@MainActor
enum LaunchAtLogin {
    /// Set once the app has either applied the default or the user has toggled
    /// the setting. Keeps a later "off" from being turned back on at next launch.
    private static let choiceKey = "launchAtLoginChoiceMade"

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    /// Opens the notch on the next login, the first time the real app runs.
    /// A toggle-off after that stays off.
    static func enableByDefault() {
        guard isAvailable else { return }
        guard !UserDefaults.standard.bool(forKey: choiceKey) else { return }
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: choiceKey)
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
