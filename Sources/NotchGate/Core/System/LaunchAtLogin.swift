import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService`. Only works when running from an `.app`
/// bundle; under `swift run` it reports itself as unavailable.
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
