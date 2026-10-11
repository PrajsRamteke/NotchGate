import AppKit
import Foundation
import Observation

/// Backs the Resume widget: lists the most recent Claude Code sessions that
/// aren't running, and opens Terminal to resume one or start a new one.
///
/// Transcripts are only scanned while the widget is visible (each time the
/// hover panel opens, at most every `minimumInterval`), never on a timer.
@MainActor
@Observable
final class ResumeMonitor {
    /// Most recent first, at most `limit`.
    private(set) var recent: [PastSession] = []
    /// The first scan hasn't finished yet.
    private(set) var isLoading = false
    /// Why the transcripts couldn't be read.
    private(set) var loadError: String?
    /// Why the last resume or new session didn't start.
    private(set) var launchError: String?
    /// What's being launched right now: a session id, or `newSessionKey`.
    private(set) var launching: String?
    /// Showing sample sessions (snapshots); nothing is read or launched.
    private(set) var isPreviewing = false

    let settings: AppSettings

    static let limit = 3
    static let newSessionKey = "new"
    /// Scans closer together than this reuse the last result.
    static let minimumInterval: TimeInterval = 10
    /// Buttons stay disabled this long after a launch, so a double click doesn't open two windows.
    static let launchCooldown: Duration = .seconds(2)

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let launcher: @MainActor (ClaudeLauncher.Mode, String?, @escaping @MainActor (ClaudeLauncher.LaunchError?) -> Void) -> Void
    @ObservationIgnored private var cache: SessionHistory.Cache = [:]
    @ObservationIgnored private var lastScan: (at: Date, excluding: Set<String>)?
    @ObservationIgnored private var scan: Task<Void, Never>?

    init(
        settings: AppSettings,
        root: URL = SessionHistory.projectsDirectory,
        launcher: @escaping @MainActor (ClaudeLauncher.Mode, String?, @escaping @MainActor (ClaudeLauncher.LaunchError?) -> Void) -> Void
            = { ClaudeLauncher.launch($0, in: $1, completion: $2) }
    ) {
        self.settings = settings
        self.root = root
        self.launcher = launcher
    }

    var isEnabled: Bool { settings.resumeWidget || isPreviewing }

    /// Where "New session" starts by default: the most recent session's folder, if it still exists.
    var defaultDirectory: String? {
        recentDirectories.first
    }

    /// Distinct folders of recent sessions that still exist, newest first.
    var recentDirectories: [String] {
        var seen = Set<String>()
        return recent.map(\.directory).filter { seen.insert($0).inserted && Self.folderExists($0) }
    }

    /// Re-reads the transcripts unless that happened moments ago with the same running sessions.
    /// - Parameter running: ids of sessions in the activity list, which aren't offered for resuming.
    func refresh(excluding running: Set<String>, force: Bool = false, now: Date = Date()) {
        guard isEnabled, !isPreviewing, scan == nil else { return }
        if !force, let lastScan, lastScan.excluding == running,
           now.timeIntervalSince(lastScan.at) < Self.minimumInterval { return }
        lastScan = (now, running)
        if recent.isEmpty, loadError == nil { isLoading = true }

        let root = root, cache = cache, limit = Self.limit
        scan = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { () throws(SessionHistory.ScanError) in
                    try SessionHistory.recent(in: root, limit: limit, excluding: running, cache: cache)
                }
            }.value
            guard let self else { return }
            scan = nil
            isLoading = false
            switch result {
            case .success(let found):
                self.cache = found.cache
                if found.sessions != recent { recent = found.sessions }
                loadError = nil
            case .failure(let error):
                loadError = error.localizedDescription
                Log.app.error("Session history scan failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func resume(_ session: PastSession) {
        start(.resume(sessionID: session.id), in: session.directory, key: session.id)
    }

    /// Starts a fresh session in `directory` (Terminal's default folder when `nil`).
    func startNew(in directory: String?) {
        start(.new, in: directory, key: Self.newSessionKey)
    }

    /// Asks for a folder, then starts a new session there.
    func chooseFolderAndStartNew() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Start Claude Code"
        panel.message = "Choose a folder for the new Claude Code session"
        panel.directoryURL = defaultDirectory.map { URL(fileURLWithPath: $0) }
        // The notch is a non-activating panel; the open panel needs the app in front.
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.startNew(in: url.path) }
        }
    }

    func dismissError() {
        launchError = nil
        loadError = nil
    }

    func setEnabled(_ enabled: Bool) {
        settings.resumeWidget = enabled
        if !enabled {
            scan?.cancel()
            scan = nil
            lastScan = nil
            recent = []
            cache = [:]
            launchError = nil
            loadError = nil
            isLoading = false
        }
    }

    /// Shows `samples` (empty: the "nothing to resume" state) without reading or launching anything.
    func showPreview(_ samples: [PastSession]) {
        isPreviewing = true
        recent = samples
    }

    // MARK: Private

    private func start(_ mode: ClaudeLauncher.Mode, in directory: String?, key: String) {
        guard launching == nil else { return }
        launchError = nil
        guard !isPreviewing else { return }
        launching = key
        launcher(mode, directory) { [weak self] error in
            guard let self else { return }
            if let error {
                launchError = error.localizedDescription
                launching = nil
                // A vanished folder means the list is out of date.
                if case .folderMissing = error { lastScan = nil }
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: Self.launchCooldown)
                self?.launching = nil
            }
        }
    }

    static func folderExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
