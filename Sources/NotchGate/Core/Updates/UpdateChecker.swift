import Foundation
import Observation

/// Knows whether a newer NotchGate is on GitHub and drives the update.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(UpdateInfo)
        case updating
        case failed(String)
        /// Development builds (`swift run`) and builds without a recorded commit.
        case unsupported
    }

    static let checkInterval: Duration = .seconds(6 * 60 * 60)
    static let launchDelay: Duration = .seconds(20)

    private(set) var state: State = .idle
    /// The last update we found; kept while re-checking so the banner doesn't flicker.
    private(set) var available: UpdateInfo?

    /// Commit this build was made from (written by `Scripts/bundle.sh`).
    let installedCommit: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var schedule: Task<Void, Never>?

    init(settings: AppSettings, bundle: Bundle = .main) {
        self.settings = settings
        let commit = bundle.object(forInfoDictionaryKey: "NotchGateCommit") as? String
        let isAppBundle = bundle.bundleURL.pathExtension == "app"
        installedCommit = (isAppBundle && commit != nil && commit != "unknown") ? commit : nil
        if installedCommit == nil { state = .unsupported }
    }

    var shortInstalledCommit: String? { installedCommit.map { String($0.prefix(7)) } }
    var isUpdateAvailable: Bool { available != nil }

    /// Checks shortly after launch, then periodically while enabled.
    func start() {
        guard installedCommit != nil else { return }
        schedule?.cancel()
        schedule = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                if self?.settings.checkForUpdates == true { await self?.check(userInitiated: false) }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func check(userInitiated: Bool = true) async {
        guard let installedCommit, state != .updating, state != .checking else { return }
        state = .checking
        do {
            let info = try await UpdateSource.compare(installedSHA: installedCommit)
            available = info.aheadBy > 0 ? info : nil
            state = available.map(State.available) ?? .upToDate(checkedAt: .now)
        } catch let failure as UpdateSource.Failure {
            // Background checks fail quietly; only a manual check reports problems.
            state = userInitiated ? .failed(failure.localizedDescription) : (available.map(State.available) ?? .idle)
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Shows an update without asking GitHub (previews and snapshots).
    func showPreview(_ info: UpdateInfo) {
        available = info
        state = .available(info)
    }

    /// Builds and installs the latest version, then relaunches NotchGate.
    func update() async {
        guard state != .updating else { return }
        if let problem = await Updater.preflight() {
            state = .failed(problem)
            return
        }
        state = .updating
        do {
            try Updater.start { [weak self] status in
                // Still alive after a successful install means the installer couldn't quit us; restart ourselves.
                if status == 0 {
                    Updater.relaunch()
                } else {
                    self?.state = .failed("The update failed (exit \(status)). See the log for details.")
                }
            }
        } catch {
            state = .failed("Couldn't start the update: \(error.localizedDescription)")
        }
    }
}
