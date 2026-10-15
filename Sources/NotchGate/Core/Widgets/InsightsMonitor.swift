import Foundation
import Observation

/// Backs the Insights widget: Claude Code's cost, tokens and activity over
/// the last 24 hours, 7 days and 30 days, read from its transcripts.
///
/// Transcripts are only read while the card is visible (each time the hover
/// panel opens, at most every `minimumInterval`), never on a timer. The first
/// read takes under a second in the background; after that only new lines are
/// read, so a refresh costs milliseconds.
@MainActor
@Observable
final class InsightsMonitor {
    /// Every range, worked out together so switching between them is instant.
    private(set) var summaries: [InsightsRange: InsightsSummary] = [:]
    /// The first read hasn't finished yet.
    private(set) var isLoading = false
    /// Why the transcripts couldn't be read.
    private(set) var loadError: String?
    /// Showing sample numbers (snapshots); nothing is read.
    private(set) var isPreviewing = false

    let settings: AppSettings

    /// Reads closer together than this reuse the last result.
    static let minimumInterval: TimeInterval = 15

    @ObservationIgnored private let root: URL
    @ObservationIgnored private var cache: TranscriptScanner.Cache = [:]
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var scan: Task<Void, Never>?

    init(settings: AppSettings, root: URL = SessionHistory.projectsDirectory) {
        self.settings = settings
        self.root = root
    }

    var isEnabled: Bool { settings.insightsWidget || isPreviewing }

    func summary(for range: InsightsRange) -> InsightsSummary? { summaries[range] }

    /// Reads what changed in the transcripts, unless that happened moments ago.
    func refresh(force: Bool = false, now: Date = Date()) {
        guard isEnabled, !isPreviewing, scan == nil else { return }
        if !force, let lastScan, now.timeIntervalSince(lastScan) < Self.minimumInterval { return }
        lastScan = now
        if summaries.isEmpty, loadError == nil { isLoading = true }

        let root = root, cache = cache
        scan = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { () throws(SessionHistory.ScanError) in
                    let since = now.addingTimeInterval(-InsightsRange.longestWindow)
                    let files = try TranscriptScanner.scan(root: root, since: since, cache: cache)
                    let summaries = Dictionary(uniqueKeysWithValues: InsightsRange.allCases.map {
                        ($0, InsightsSummary.make($0, from: files.values, now: now))
                    })
                    return (files, summaries)
                }
            }.value
            guard let self else { return }
            scan = nil
            isLoading = false
            switch result {
            case .success(let (files, summaries)):
                self.cache = files
                if summaries != self.summaries { self.summaries = summaries }
                loadError = nil
            case .failure(let error):
                loadError = error.localizedDescription
                Log.app.error("Insights scan failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.insightsWidget = enabled
        if !enabled {
            scan?.cancel()
            scan = nil
            lastScan = nil
            summaries = [:]
            cache = [:]
            loadError = nil
            isLoading = false
        }
    }

    /// Shows `samples` without reading anything (snapshots).
    func showPreview(_ samples: [InsightsRange: InsightsSummary]) {
        isPreviewing = true
        summaries = samples
    }
}
