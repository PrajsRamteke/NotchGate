import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Tool activity widget")
struct ToolUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func groupsToolsIntoCategories() {
        #expect(ToolUsage.Category(toolName: "Bash") == .run)
        #expect(ToolUsage.Category(toolName: "MultiEdit") == .edit)
        #expect(ToolUsage.Category(toolName: "Write") == .edit)
        #expect(ToolUsage.Category(toolName: "Read") == .read)
        #expect(ToolUsage.Category(toolName: "Grep") == .search)
        #expect(ToolUsage.Category(toolName: "Glob") == .search)
        #expect(ToolUsage.Category(toolName: "WebFetch") == .web)
        #expect(ToolUsage.Category(toolName: "Agent") == .agent)
        #expect(ToolUsage.Category(toolName: "mcp__github__create_issue") == .mcp)
        #expect(ToolUsage.Category(toolName: "TodoWrite") == .other)
    }

    @Test func countsAndRanksCalls() {
        var usage = ToolUsage()
        for tool in ["Bash", "Read", "Read", "Edit", "Read", "Bash"] {
            usage.record(toolName: tool, at: now)
        }
        #expect(usage.total == 6)
        #expect(usage.count(.read) == 3)
        #expect(usage.count(.web) == 0)
        #expect(usage.ranked.map(\.category) == [.read, .run, .edit])
        #expect(usage.lastCallAt == now)
    }

    @Test func timelineBucketsTheLastHour() {
        var usage = ToolUsage()
        usage.record(toolName: "Bash", at: now)
        usage.record(toolName: "Bash", at: now.addingTimeInterval(-60))
        usage.record(toolName: "Read", at: now.addingTimeInterval(-10 * 60))
        // Older than the hour shown: counted, but not in the strip.
        usage.record(toolName: "Read", at: now.addingTimeInterval(-90 * 60))

        let timeline = usage.timeline(endingAt: now, buckets: 30, bucketMinutes: 2)
        #expect(timeline.count == 30)
        #expect(timeline.last == 2)
        #expect(timeline[timeline.count - 6] == 1)
        #expect(timeline.reduce(0, +) == 3)
        #expect(usage.total == 4)
    }

    @Test func forgetsMinutesPastTheHistory() {
        var usage = ToolUsage()
        usage.record(toolName: "Bash", at: now)
        usage.record(toolName: "Bash", at: now.addingTimeInterval(2 * 3600))
        #expect(usage.minutes.count == 1)
        #expect(usage.count(.run) == 2)
    }

    @Test func combinesSessions() {
        var api = ToolUsage(), web = ToolUsage()
        api.record(toolName: "Bash", at: now)
        web.record(toolName: "Bash", at: now.addingTimeInterval(30))
        web.record(toolName: "Edit", at: now.addingTimeInterval(30))
        let both = ToolUsage.combined([api, web])
        #expect(both.count(.run) == 2)
        #expect(both.count(.edit) == 1)
        #expect(both.lastCallAt == now.addingTimeInterval(30))
        #expect(both.timeline(endingAt: now.addingTimeInterval(30), buckets: 1, bucketMinutes: 2) == [3])
    }

    // MARK: Reducer

    private func event(_ event: HookEvent, _ fields: [String: JSONValue] = [:]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string("s1")
        payload["cwd"] = .string("/tmp/shop")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 9))
    }

    private func tool(_ name: String) -> BridgeRequest {
        event(.preToolUse, ["tool_name": .string(name), "tool_input": .object([:])])
    }

    private func run(_ events: [BridgeRequest]) -> SessionActivity? {
        events.reduce([:]) { ActivityReducer.reduce($0, $1, now: now) }["s1"]
    }

    @Test func reducerCountsToolsAcrossTurns() throws {
        let session = try #require(run([
            event(.userPromptSubmit), tool("Bash"), tool("Read"), event(.stop),
            event(.userPromptSubmit), tool("Read"), tool("AskUserQuestion"), tool("ExitPlanMode"),
        ]))
        // Per-turn count resets; the session's usage doesn't, and questions/plans aren't tools.
        #expect(session.toolCount == 1)
        #expect(session.toolUsage.total == 3)
        #expect(session.toolUsage.count(.read) == 2)
    }

    @Test func newSessionStartsOverButCompactionKeepsCounts() throws {
        let compacted = try #require(run([tool("Bash"), event(.sessionStart, ["source": .string("compact")])]))
        #expect(compacted.toolUsage.total == 1)

        let cleared = try #require(run([tool("Bash"), event(.sessionStart, ["source": .string("clear")])]))
        #expect(cleared.toolUsage.isEmpty)
    }
}
