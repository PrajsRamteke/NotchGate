import Foundation
import NotchGateKit
import Observation

/// Backs the Session widget: keeps the status line relay installed while the
/// widget is on, and picks up each session's details the relay saves.
@MainActor
@Observable
final class SessionMonitor {
    /// Every recently reported session, by Claude Code session id.
    private(set) var snapshots: [String: SessionSnapshot] = [:]
    /// Why the relay couldn't be installed, shown in the menu bar.
    private(set) var setupError: String?
    /// Showing sample sessions (snapshots); nothing is installed or read.
    private(set) var isPreviewing = false

    let settings: AppSettings

    @ObservationIgnored private let installer: StatusLineInstaller
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var poller: Task<Void, Never>?
    /// Each file's modification date and contents as last read, so only changed files are decoded.
    @ObservationIgnored private var files: [URL: (modified: Date, snapshot: SessionSnapshot)] = [:]

    /// The relay writes files; listing their dates is cheap.
    static let pollInterval: Duration = .seconds(5)
    /// Files of sessions that haven't reported for this long are deleted.
    static let retention: TimeInterval = 24 * 3600

    init(
        settings: AppSettings,
        installer: StatusLineInstaller = StatusLineInstaller(),
        directory: URL = BridgeLocation.sessionsDirectory
    ) {
        self.settings = settings
        self.installer = installer
        self.directory = directory
    }

    var isEnabled: Bool { settings.sessionWidget || isPreviewing }

    /// The session that reported most recently.
    var latest: SessionSnapshot? {
        snapshots.values.max { $0.updatedAt < $1.updatedAt }
    }

    func snapshot(for sessionID: String) -> SessionSnapshot? {
        snapshots[sessionID]
    }

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

    /// Shows `samples` (empty: the waiting state) without touching settings or the status line.
    func showPreview(_ samples: [SessionSnapshot]) {
        isPreviewing = true
        snapshots = Dictionary(samples.map { ($0.sessionID, $0) }, uniquingKeysWith: { $1 })
    }

    /// Picks up new and changed session files, and deletes ones past `retention`.
    func reload(now: Date = Date()) {
        let listed = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []

        var fresh: [URL: (modified: Date, snapshot: SessionSnapshot)] = [:]
        for file in listed where file.pathExtension == "json" {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { continue }
            if now.timeIntervalSince(modified) > Self.retention {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            if let cached = files[file], cached.modified == modified {
                fresh[file] = cached
            } else if let snapshot = SessionSnapshot.load(from: file) {
                fresh[file] = (modified, snapshot)
            }
        }
        files = fresh

        let next = Dictionary(
            fresh.values.map { ($0.snapshot.sessionID, $0.snapshot) },
            uniquingKeysWith: { $0.updatedAt >= $1.updatedAt ? $0 : $1 }
        )
        if next != snapshots { snapshots = next }
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
