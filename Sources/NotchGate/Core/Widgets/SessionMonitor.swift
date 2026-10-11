import Foundation
import NotchGateKit
import Observation

/// Backs the Session widget: keeps the status line relay installed while the
/// widget is on, and picks up the latest session details the relay saves.
@MainActor
@Observable
final class SessionMonitor {
    private(set) var snapshot: SessionSnapshot?
    /// Why the relay couldn't be installed, shown in the menu bar.
    private(set) var setupError: String?
    /// Showing a sample session (snapshots); nothing is installed or read.
    private(set) var isPreviewing = false

    let settings: AppSettings

    @ObservationIgnored private let installer: StatusLineInstaller
    @ObservationIgnored private let snapshotURL: URL
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var lastModified: Date?

    /// The relay writes a file; checking its date is cheap.
    static let pollInterval: Duration = .seconds(5)

    init(
        settings: AppSettings,
        installer: StatusLineInstaller = StatusLineInstaller(),
        snapshotURL: URL = BridgeLocation.sessionURL
    ) {
        self.settings = settings
        self.installer = installer
        self.snapshotURL = snapshotURL
    }

    var isEnabled: Bool { settings.sessionWidget || isPreviewing }

    func start() {
        guard isEnabled else { return }
        installRelay()
        startPolling()
    }

    /// Stops watching; the relay stays while any other status line widget needs it.
    func stop() {
        poller?.cancel()
        poller = nil
    }

    func setEnabled(_ enabled: Bool) {
        settings.sessionWidget = enabled
        if enabled {
            installRelay()
            startPolling()
        } else {
            stop()
            setupError = nil
            do {
                try installer.removeIfUnused(settings)
            } catch {
                Log.hooks.error("Status line restore failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Shows `sample` (`nil`: the waiting state) without touching settings or the status line.
    func showPreview(_ sample: SessionSnapshot?) {
        isPreviewing = true
        snapshot = sample
    }

    /// Reads the snapshot again if the relay has written a new one.
    func reload() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: snapshotURL.path))?[.modificationDate] as? Date
        guard modified != lastModified || snapshot == nil else { return }
        lastModified = modified
        let loaded = SessionSnapshot.load(from: snapshotURL)
        if loaded != snapshot { snapshot = loaded }
    }

    // MARK: Private

    private func installRelay() {
        do {
            try installer.install()
            setupError = nil
        } catch {
            setupError = error.localizedDescription
            Log.hooks.error("Status line relay install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPolling() {
        reload()
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                self?.reload()
            }
        }
    }
}
