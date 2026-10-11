import Darwin
import Foundation
import NotchGateKit
import Observation

/// Holds the live activity of every Claude Code session for the hover panel.
@MainActor
@Observable
final class ActivityTracker {
    private(set) var sessions: [String: SessionActivity] = [:]

    /// Sessions that ended without a `SessionEnd` (terminal closed, crash)
    /// disappear once they have been quiet this long.
    static let staleAfter: TimeInterval = 6 * 60 * 60

    /// Most relevant first: working, then waiting on you, then most recent.
    var ordered: [SessionActivity] {
        sessions.values.sorted { lhs, rhs in
            if lhs.isWorking != rhs.isWorking { return lhs.isWorking }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var workingCount: Int { sessions.values.filter(\.isWorking).count }

    func ingest(_ message: BridgeRequest) {
        sessions = ActivityReducer.reduce(sessions, message)
    }

    /// Drops sessions whose Claude process is gone or that went stale.
    func prune(now: Date = .now) {
        sessions = sessions.filter { _, session in
            guard now.timeIntervalSince(session.updatedAt) < Self.staleAfter else { return false }
            guard session.claudePID > 0 else { return true }
            return kill(session.claudePID, 0) == 0 || errno != ESRCH
        }
    }

    /// Seeds sample sessions for previews and snapshots.
    func load(_ samples: [SessionActivity]) {
        sessions = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
    }
}
