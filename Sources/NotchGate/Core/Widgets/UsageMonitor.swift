import Foundation
import NotchGateKit
import Observation

/// Backs the Usage widget: keeps the status line relay installed while the
/// widget is on, and picks up the plan limits it saves.
///
/// Claude Code only reports limits to the status line, and only for Pro and
/// Max plans, so the numbers are as fresh as the last reply in any session.
@MainActor
@Observable
final class UsageMonitor {
    private(set) var snapshot: UsageSnapshot?
    /// Why the relay couldn't be installed, shown in the menu bar.
    private(set) var setupError: String?
    /// Showing sample numbers (snapshots); nothing is installed or read.
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
        snapshotURL: URL = BridgeLocation.usageURL
    ) {
        self.settings = settings
        self.installer = installer
        self.snapshotURL = snapshotURL
    }

    var isEnabled: Bool { settings.usageWidget || isPreviewing }

    func start() {
        guard isEnabled else { return }
        installRelay()
        startPolling()
    }

    /// Stops watching; the relay stays so the numbers keep coming while the app is closed.
    func stop() {
        poller?.cancel()
        poller = nil
    }

    func setEnabled(_ enabled: Bool) {
        settings.usageWidget = enabled
        if enabled {
            installRelay()
            startPolling()
        } else {
            stop()
            setupError = nil
            do {
                try installer.uninstall()
            } catch {
                Log.hooks.error("Status line restore failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Shows `sample` (`nil`: the waiting state) without touching settings or the status line.
    func showPreview(_ sample: UsageSnapshot?) {
        isPreviewing = true
        snapshot = sample
    }

    /// Reads the snapshot again if the relay has written a new one.
    func reload() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: snapshotURL.path))?[.modificationDate] as? Date
        guard modified != lastModified || snapshot == nil else { return }
        lastModified = modified
        let loaded = UsageSnapshot.load(from: snapshotURL)
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

/// One limit as the widget shows it: rounded percentage, severity and a
/// short reset phrase.
struct UsageGauge: Equatable {
    enum Level: Equatable {
        case normal, high, critical
    }

    let title: String
    let percent: Int
    let fraction: Double
    let level: Level
    let resetText: String

    init(title: String, window: UsageSnapshot.Window?, now: Date) {
        self.title = title
        // Claude Code drops a window once it resets; a stale snapshot may still have it.
        guard let window, !window.hasReset(at: now) else {
            percent = 0
            fraction = 0
            level = .normal
            resetText = "Fresh window"
            return
        }
        percent = Int(window.usedPercentage.rounded())
        fraction = window.usedPercentage / 100
        level = window.usedPercentage >= 90 ? .critical : window.usedPercentage >= 75 ? .high : .normal
        resetText = Self.resetPhrase(until: window.resetsAt, now: now)
    }

    static func fiveHour(_ snapshot: UsageSnapshot, now: Date) -> UsageGauge {
        UsageGauge(title: "5-hour limit", window: snapshot.fiveHour, now: now)
    }

    static func weekly(_ snapshot: UsageSnapshot, now: Date) -> UsageGauge {
        UsageGauge(title: "Weekly limit", window: snapshot.sevenDay, now: now)
    }

    /// "Resets in 42m", "Resets in 3h 12m", or "Resets Tue 9:00 AM" when it's a day or more away.
    static func resetPhrase(until reset: Date, now: Date) -> String {
        let minutes = Int((reset.timeIntervalSince(now) / 60).rounded(.up))
        switch minutes {
        case ..<1: return "Resets in under a minute"
        case ..<60: return "Resets in \(minutes)m"
        case ..<(24 * 60):
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "Resets in \(hours)h" : "Resets in \(hours)h \(rest)m"
        default:
            return "Resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
    }

    /// "Updated just now", "Updated 4m ago", "Updated 2h ago", "Updated 3d ago".
    static func updatedPhrase(_ updated: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(updated) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes)m ago"
        case ..<(24 * 60): return "Updated \(minutes / 60)h ago"
        default: return "Updated \(minutes / (24 * 60))d ago"
        }
    }
}
