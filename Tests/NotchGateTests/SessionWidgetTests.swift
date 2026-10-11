import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Session widget")
struct SessionWidgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func statusLine(context: JSONValue? = nil, cost: Double? = 0.42) -> JSONValue {
        var input: [String: JSONValue] = [
            "session_id": .string("abc123"),
            "model": .object(["display_name": .string("Opus")]),
            "workspace": .object(["project_dir": .string("/Users/me/NotchGate")]),
        ]
        if let context { input["context_window"] = context }
        if let cost { input["cost"] = .object(["total_cost_usd": .number(cost)]) }
        return .object(input)
    }

    @Test func readsModelContextCostAndBranch() throws {
        let input = statusLine(context: .object([
            "used_percentage": .number(42.4),
            "context_window_size": .number(200_000),
        ]))
        let snapshot = try #require(SessionSnapshot(statusLine: input, branch: "main", now: now))
        #expect(snapshot.sessionID == "abc123")
        #expect(snapshot.projectName == "NotchGate")
        #expect(snapshot.model == "Opus")
        #expect(snapshot.contextPercent == 42.4)
        #expect(snapshot.contextSize == 200_000)
        #expect(snapshot.costUSD == 0.42)
        #expect(snapshot.branch == "main")
        #expect(snapshot.updatedAt == now)
    }

    @Test func missingSessionIdMeansNoSnapshot() {
        let input: JSONValue = .object(["model": .object(["display_name": .string("Opus")])])
        #expect(SessionSnapshot(statusLine: input, branch: nil, now: now) == nil)
    }

    @Test func missingFieldsStayNil() throws {
        let snapshot = try #require(SessionSnapshot(statusLine: statusLine(cost: nil), branch: nil, now: now))
        #expect(snapshot.contextPercent == nil)
        #expect(snapshot.costUSD == nil)
        #expect(snapshot.branch == nil)
    }

    @Test func clampsContextPercentage() throws {
        let input = statusLine(context: .object(["used_percentage": .number(130)]))
        #expect(try #require(SessionSnapshot(statusLine: input, branch: nil, now: now)).contextPercent == 100)
    }

    private func sample(_ id: String, cost: Double = 1.5, updatedAt: Date? = nil) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: id, directory: "/Users/me/\(id)", model: "Sonnet", contextPercent: 12,
            contextSize: 1_000_000, costUSD: cost, branch: "feature/x", updatedAt: updatedAt ?? now
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID())", isDirectory: true)
    }

    @Test func savesEachSessionToItsOwnFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try sample("one").save(in: directory)
        try sample("two").save(in: directory)
        #expect(SessionSnapshot.load(from: SessionSnapshot.fileURL(for: "one", in: directory)) == sample("one"))
        #expect(SessionSnapshot.load(from: SessionSnapshot.fileURL(for: "two", in: directory)) == sample("two"))
    }

    @Test func sessionFileStaysInsideItsFolder() {
        let directory = URL(fileURLWithPath: "/tmp/sessions")
        #expect(SessionSnapshot.fileURL(for: "../../evil", in: directory).path == "/tmp/sessions/evil.json")
    }

    @MainActor
    @Test func monitorKeepsEverySessionApart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "session-\(UUID())")!)
        let monitor = SessionMonitor(settings: settings, directory: directory)

        try sample("one", cost: 1, updatedAt: now).save(in: directory)
        try sample("two", cost: 2, updatedAt: now.addingTimeInterval(60)).save(in: directory)
        monitor.reload()

        #expect(monitor.snapshots.count == 2)
        #expect(monitor.snapshot(for: "one")?.costUSD == 1)
        #expect(monitor.snapshot(for: "two")?.costUSD == 2)
        #expect(monitor.latest?.sessionID == "two")

        // A new reply in one session updates only that session.
        try sample("one", cost: 3, updatedAt: now.addingTimeInterval(120)).save(in: directory)
        let file = SessionSnapshot.fileURL(for: "one", in: directory)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: file.path)
        monitor.reload()
        #expect(monitor.snapshot(for: "one")?.costUSD == 3)
        #expect(monitor.snapshot(for: "two")?.costUSD == 2)
        #expect(monitor.latest?.sessionID == "one")
    }

    @MainActor
    @Test func monitorDeletesSessionsPastRetention() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "session-\(UUID())")!)
        let monitor = SessionMonitor(settings: settings, directory: directory)

        try sample("old").save(in: directory)
        try sample("new").save(in: directory)
        let old = SessionSnapshot.fileURL(for: "old", in: directory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-SessionMonitor.retention - 60)],
            ofItemAtPath: old.path
        )
        monitor.reload()

        #expect(monitor.snapshots.keys.sorted() == ["new"])
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func shortensTokenCounts() {
        #expect(SessionUsageDetails.tokenPhrase(200_000) == "200K")
        #expect(SessionUsageDetails.tokenPhrase(1_000_000) == "1M")
        #expect(SessionUsageDetails.tokenPhrase(800) == "800")
    }

    @Test func ignoresAnOutOfRangeContextSize() throws {
        let input = statusLine(context: .object(["context_window_size": .number(1e300)]))
        #expect(try #require(SessionSnapshot(statusLine: input, branch: nil, now: now)).contextSize == nil)
    }

    @Test func readsTheBranchFromGitHEAD() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("repo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let git = root.appendingPathComponent(".git")
        let nested = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        try "ref: refs/heads/feature/x\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: nested.path) == "feature/x")

        try "3f2a9c1d\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: root.path) == nil)
    }

    @Test func readsTheBranchOfALinkedWorktree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("worktree-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let gitDir = root.appendingPathComponent("main/.git/worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "ref: refs/heads/fix\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "gitdir: \(gitDir.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        #expect(GitBranch.current(in: worktree.path) == "fix")
    }

    @Test func noBranchOutsideARepository() {
        #expect(GitBranch.current(in: "") == nil)
    }
}
