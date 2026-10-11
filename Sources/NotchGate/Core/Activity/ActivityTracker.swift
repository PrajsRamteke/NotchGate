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

    /// Paths a running `rm` is about to delete, by `tool_use_id`.
    @ObservationIgnored private var pendingRemovals: [String: [String]] = [:]
    @ObservationIgnored private let fileExists: (String) -> Bool

    init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    func ingest(_ message: BridgeRequest) {
        sessions = ActivityReducer.reduce(sessions, message, removedPaths: removedPaths(by: message))
    }

    /// Hooks don't say what a shell command deleted, so look: note which of
    /// the files an `rm` names exist before it runs, and which are gone after.
    private func removedPaths(by message: BridgeRequest) -> [String] {
        let payload = message.payload
        guard payload["tool_name"]?.stringValue == "Bash",
              let id = payload["tool_use_id"]?.stringValue else { return [] }
        switch message.event {
        case .preToolUse:
            let command = payload["tool_input"]?["command"]?.stringValue ?? ""
            let cwd = payload["cwd"]?.stringValue ?? ""
            let existing = RemovalCommand.paths(in: command, cwd: cwd).filter(fileExists)
            guard !existing.isEmpty else { return [] }
            // A failed command never reports back; don't let those pile up.
            if pendingRemovals.count >= 64 { pendingRemovals.removeAll() }
            pendingRemovals[id] = existing
            return []
        case .postToolUse:
            return (pendingRemovals.removeValue(forKey: id) ?? []).filter { !fileExists($0) }
        default:
            return []
        }
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
