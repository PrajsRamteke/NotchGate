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

    /// Sessions the user removed from the panel, with when each was last heard
    /// from. Their events are ignored until the user prompts them again.
    private(set) var dismissed: [String: Date] = [:]

    /// Paths a running `rm` is about to delete, by `tool_use_id`.
    @ObservationIgnored private var pendingRemovals: [String: [String]] = [:]
    @ObservationIgnored private let fileExists: (String) -> Bool

    /// The project's files as of the last look, per session. Shell commands
    /// change files without saying so; a later look shows what they did.
    @ObservationIgnored private var baselines: [String: WorkingTreeSnapshot] = [:]
    /// The look in progress per session; each waits for the one before it.
    @ObservationIgnored private var scans: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let captureWorkingTree: @Sendable (String) async -> WorkingTreeSnapshot?

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        captureWorkingTree: @escaping @Sendable (String) async -> WorkingTreeSnapshot? = { await WorkingTreeSnapshot.capture(cwd: $0) }
    ) {
        self.fileExists = fileExists
        self.captureWorkingTree = captureWorkingTree
    }

    func ingest(_ message: BridgeRequest, now: Date = .now) {
        if let id = message.payload["session_id"]?.stringValue, dismissed[id] != nil {
            let isCompaction = message.payload["source"]?.stringValue == "compact"
            switch message.event {
            case .userPromptSubmit:
                // The user is back in this session: show it again, starting from here.
                dismissed[id] = nil
            case .sessionStart where !isCompaction:
                // Started over (`/clear`, resumed): also the user's doing.
                dismissed[id] = nil
            case .sessionEnd:
                dismissed[id] = nil
                return
            default:
                dismissed[id] = now
                return
            }
        }
        sessions = ActivityReducer.reduce(sessions, message, removedPaths: removedPaths(by: message), now: now)
        trackWorkingTree(message)
    }

    /// Waits for the file looks in progress to finish.
    func settleFileChanges() async {
        for scan in Array(scans.values) { await scan.value }
    }

    /// Finds what shell commands changed. A baseline is taken when a turn
    /// starts; after every `Bash` call and at the end of the turn, the files
    /// are looked at again and the difference is what that command did.
    private func trackWorkingTree(_ message: BridgeRequest) {
        let payload = message.payload
        guard let id = payload["session_id"]?.stringValue else { return }
        if message.event == .sessionEnd {
            scans.removeValue(forKey: id)?.cancel()
            baselines[id] = nil
            return
        }
        guard let cwd = sessions[id]?.cwd, !cwd.isEmpty else { return }
        let isBash = payload["tool_name"]?.stringValue == "Bash"
        switch message.event {
        case .sessionStart where payload["source"]?.stringValue != "compact":
            // Starting over: a look still running belongs to the old session.
            scans[id]?.cancel()
            scan(id, cwd: cwd, recordChanges: false)
        case .userPromptSubmit:
            scan(id, cwd: cwd, recordChanges: false)
        case .preToolUse where isBash && baselines[id] == nil:
            scan(id, cwd: cwd, recordChanges: false)
        case .postToolUse where isBash, .stop:
            scan(id, cwd: cwd, recordChanges: true)
        default:
            break
        }
    }

    private func scan(_ id: String, cwd: String, recordChanges: Bool) {
        let previous = scans[id]
        let capture = captureWorkingTree
        scans[id] = Task {
            await previous?.value
            let snapshot = await capture(cwd)
            guard !Task.isCancelled, let snapshot, sessions[id] != nil else { return }
            if recordChanges, let baseline = baselines[id] {
                for change in snapshot.changes(since: baseline, exists: fileExists) {
                    sessions[id]?.fileChanges.record(change.kind, path: change.path)
                }
            }
            baselines[id] = snapshot
        }
    }

    /// Removes a stopped session from the panel; Claude keeps running. It comes
    /// back when the user sends it a prompt or starts it over.
    /// - Returns: `false` (and keeps it) while the session is mid-turn.
    @discardableResult
    func dismiss(_ id: String, now: Date = .now) -> Bool {
        guard let session = sessions[id], session.canDismiss else { return false }
        sessions[id] = nil
        dismissed[id] = now
        return true
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
        dismissed = dismissed.filter { now.timeIntervalSince($0.value) < Self.staleAfter }
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
