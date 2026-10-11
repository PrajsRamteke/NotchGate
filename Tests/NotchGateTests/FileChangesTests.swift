import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("File changes")
@MainActor
struct FileChangesTests {
    private func event(_ event: HookEvent, _ fields: [String: JSONValue]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string("s1")
        payload["cwd"] = .string("/tmp/shop")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 9))
    }

    /// A file tool's `PostToolUse` as the hook forwards it (after `sanitize`).
    private func fileTool(_ tool: String, path: String, response: JSONValue, content: String? = nil) -> BridgeRequest {
        var input: [String: JSONValue] = ["file_path": .string(path)]
        if let content { input["content"] = .string(content) }
        let raw = JSONValue.object([
            "tool_name": .string(tool),
            "tool_input": .object(input),
            "tool_response": response,
        ])
        let forwarded = HookPolicy.sanitize(event: .postToolUse, payload: raw)
        return event(.postToolUse, forwarded.objectValue ?? [:])
    }

    private func patch(_ lines: [String]) -> JSONValue {
        .array([.object(["lines": .array(lines.map(JSONValue.string))])])
    }

    // MARK: Hook summary

    @Test func hookSummarizesTheDiffAndDropsTheBody() throws {
        let raw = JSONValue.object([
            "tool_name": .string("Edit"),
            "tool_input": .object(["file_path": .string("/tmp/shop/a.swift")]),
            "tool_response": .object([
                "originalFile": .string(String(repeating: "x", count: 10_000)),
                "structuredPatch": patch([" keep", "-old", "+new", "+more"]),
            ]),
        ])
        let forwarded = HookPolicy.sanitize(event: .postToolUse, payload: raw)
        #expect(forwarded["tool_response"] == nil)
        let change = try #require(forwarded["file_change"])
        #expect(change["created"] == .bool(false))
        #expect(change["lines_added"] == .number(2))
        #expect(change["lines_removed"] == .number(1))
    }

    @Test func aNewFileCountsItsWholeContent() {
        let change = HookPolicy.fileChange(
            tool: "Write",
            input: .object(["content": .string("one\ntwo\nthree\n")]),
            response: .object(["type": .string("create"), "structuredPatch": .array([])])
        )
        #expect(change?["created"] == .bool(true))
        #expect(change?["lines_added"] == .number(3))
    }

    // MARK: Reducer

    @Test func countsAddedChangedAndDeletedFiles() throws {
        let tracker = ActivityTracker(fileExists: { _ in false })
        tracker.ingest(fileTool("Write", path: "/tmp/shop/New.swift", response: .object(["type": .string("create")]), content: "a\nb"))
        tracker.ingest(fileTool("Edit", path: "/tmp/shop/Old.swift", response: .object(["structuredPatch": patch(["-a", "+b"])])))
        tracker.ingest(fileTool("Edit", path: "/tmp/shop/Old.swift", response: .object(["structuredPatch": patch(["+c"])])))
        tracker.ingest(fileTool("Write", path: "/tmp/shop/Readme.md", response: .object(["type": .string("update")])))

        let changes = try #require(tracker.sessions["s1"]?.fileChanges)
        #expect(changes.added == 1)
        #expect(changes.modified == 2) // Old.swift twice still counts once.
        #expect(changes.deleted == 0)
        #expect(changes.linesAdded == 4)
        #expect(changes.linesRemoved == 1)
        #expect(changes.summary == "3 files: 1 added, 2 changed · +4 −1 lines")
    }

    @Test func createdThenDeletedLeavesNoTrace() {
        var changes = FileChanges()
        changes.record(.added, path: "/tmp/shop/scratch.txt")
        changes.record(.deleted, path: "/tmp/shop/scratch.txt")
        #expect(changes.isEmpty)

        changes.record(.deleted, path: "/tmp/shop/kept.txt")
        changes.record(.added, path: "/tmp/shop/kept.txt")
        #expect(changes.modified == 1)
    }

    @Test func aNewSessionStartsFromZero() {
        let tracker = ActivityTracker(fileExists: { _ in false })
        tracker.ingest(fileTool("Edit", path: "/tmp/shop/a.swift", response: .object([:])))
        tracker.ingest(event(.sessionStart, ["source": .string("clear")]))
        #expect(tracker.sessions["s1"]?.fileChanges.isEmpty == true)
    }

    // MARK: Deletions

    @Test func countsFilesAnRmActuallyDeleted() throws {
        var onDisk: Set<String> = ["/tmp/shop/old.log", "/tmp/shop/build", "/tmp/shop/keep.txt"]
        let tracker = ActivityTracker(fileExists: { onDisk.contains($0) })
        let bash: [String: JSONValue] = [
            "tool_name": .string("Bash"),
            "tool_use_id": .string("t1"),
            "tool_input": .object(["command": .string("rm -rf old.log build missing.txt && rm keep.txt")]),
        ]
        tracker.ingest(event(.preToolUse, bash))
        // keep.txt survives (say the second rm failed); missing.txt never existed.
        onDisk = ["/tmp/shop/keep.txt"]
        tracker.ingest(event(.postToolUse, bash))

        let changes = try #require(tracker.sessions["s1"]?.fileChanges)
        #expect(changes.deleted == 2)
        #expect(changes.files["/tmp/shop/old.log"] == .deleted)
        #expect(changes.files["/tmp/shop/keep.txt"] == nil)
    }

    @Test(arguments: [
        ("rm a.txt", ["/tmp/shop/a.txt"]),
        ("rm -f -- -odd.txt 'with space.txt'", ["/tmp/shop/-odd.txt", "/tmp/shop/with space.txt"]),
        ("sudo rm /etc/x; git rm src/y.swift", ["/etc/x", "/tmp/shop/src/y.swift"]),
        ("FORCE=1 unlink ../z", ["/tmp/z"]),
        ("rm *.log $TMP/x `pwd`/y", []),
        ("echo rm a.txt | grep rm", []),
        ("git status && npm run rm", []),
    ])
    func findsLiteralPathsInRemoveCommands(command: String, expected: [String]) {
        #expect(RemovalCommand.paths(in: command, cwd: "/tmp/shop") == expected)
    }
}
