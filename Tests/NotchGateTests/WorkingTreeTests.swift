import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Working tree changes")
@MainActor
struct WorkingTreeTests {
    private func stamp(_ seconds: Double, size: UInt64 = 10) -> WorkingTreeSnapshot.Stamp {
        .init(size: size, modified: Date(timeIntervalSince1970: seconds))
    }

    private func snapshot(_ files: [String: Double?], new: Set<String> = []) -> WorkingTreeSnapshot {
        // The raw status for these files, read back through the parser.
        let status = files.keys.sorted().map { (new.contains($0) ? "?? " : " M ") + $0 }.joined(separator: "\0") + "\0"
        return WorkingTreeSnapshot.parse(status: status, root: "/repo", stamp: { path in
            files[String(path.dropFirst("/repo/".count))].flatMap { $0 }.map { stamp($0) }
        })!
    }

    @Test func findsFilesRewrittenCreatedAndDeletedByAShellCommand() {
        let before = snapshot(["a.swift": 1, "b.swift": 1, "gone.swift": 1])
        let after = snapshot(["a.swift": 2, "b.swift": 1, "gone.swift": nil, "fresh.txt": 5], new: ["fresh.txt"])

        let changes = after.changes(since: before, exists: { _ in true })
        #expect(changes.map(\.path) == ["/repo/a.swift", "/repo/fresh.txt", "/repo/gone.swift"])
        #expect(changes.map(\.kind) == [.modified, .added, .deleted])
    }

    @Test func aFileAlreadyDirtyBeforeTheCommandIsNotCounted() {
        let before = snapshot(["mine.swift": 1])
        #expect(before.changes(since: before).isEmpty)
    }

    @Test func aRemovedUntrackedFileCountsAsDeletedButARevertedOneDoesNot() {
        let before = snapshot(["scratch.txt": 1, "reverted.swift": 1], new: ["scratch.txt"])
        let after = snapshot([:])
        let changes = after.changes(since: before, exists: { $0 == "/repo/reverted.swift" })
        #expect(changes.map(\.path) == ["/repo/scratch.txt"])
        #expect(changes.map(\.kind) == [.deleted])
    }

    @Test func readsRenamesAndStagedAdds() throws {
        let status = "R  new name.swift\0old.swift\0A  staged.swift\0?? loose.txt\0 M edited.swift\0"
        let tree = try #require(WorkingTreeSnapshot.parse(status: status, root: "/repo", stamp: { _ in stamp(1) }))
        #expect(tree.entries["/repo/new name.swift"]?.isNew == true)
        #expect(tree.entries["/repo/old.swift"]?.isNew == false)
        #expect(tree.entries["/repo/staged.swift"]?.isNew == true)
        #expect(tree.entries["/repo/loose.txt"]?.isNew == true)
        #expect(tree.entries["/repo/edited.swift"]?.isNew == false)
    }

    // MARK: Tracker

    private func event(_ event: HookEvent, _ fields: [String: JSONValue] = [:]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string("s1")
        payload["cwd"] = .string("/repo")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 9))
    }

    @Test func countsFilesABashCommandChangedThatNoFileToolReported() async throws {
        let looks = Looks([
            snapshot(["a.swift": 1, "b.swift": 1]),                              // turn starts
            snapshot(["a.swift": 2, "b.swift": 2, "c.swift": 2, "n.txt": 2], new: ["n.txt"]), // after python
        ])
        let tracker = ActivityTracker(fileExists: { _ in true }, captureWorkingTree: { _ in await looks.next() })

        tracker.ingest(event(.userPromptSubmit, ["prompt": .string("go")]))
        await tracker.settleFileChanges()
        tracker.ingest(event(.postToolUse, ["tool_name": .string("Bash"), "tool_use_id": .string("t1"),
                                            "tool_input": .object(["command": .string("python3 edit.py")])]))
        await tracker.settleFileChanges()

        let changes = try #require(tracker.sessions["s1"]?.fileChanges)
        #expect(changes.modified == 3)
        #expect(changes.added == 1)
    }

    @Test func readOnlyToolsDontTriggerALook() async {
        let looks = Looks([snapshot([:])])
        let tracker = ActivityTracker(fileExists: { _ in true }, captureWorkingTree: { _ in await looks.next() })
        tracker.ingest(event(.postToolUse, ["tool_name": .string("Read")]))
        await tracker.settleFileChanges()
        #expect(await looks.taken == 0)
    }
}

private actor Looks {
    private var queue: [WorkingTreeSnapshot]
    private(set) var taken = 0

    init(_ queue: [WorkingTreeSnapshot]) { self.queue = queue }

    func next() -> WorkingTreeSnapshot? {
        taken += 1
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}
