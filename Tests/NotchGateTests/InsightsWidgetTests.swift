import Foundation
import Testing
@testable import NotchGate

@Suite("Insights widget")
struct InsightsWidgetTests {
    /// Half past an hour, so "a minute ago" is still this hour.
    private let now = Date(timeIntervalSince1970: 1_800_001_800)

    // MARK: Fixtures

    /// A fresh `projects` folder, deleted when the test's scope ends.
    private final class Projects {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("insights-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func write(_ path: String, lines: [String], newlineAtEnd: Bool = true, modified: Date) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + (newlineAtEnd ? "\n" : "")).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            return url
        }
    }

    private func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// One transcript line of a reply; a reply with several content blocks repeats it with the same ids.
    private func reply(id: String, at date: Date, model: String = "claude-opus-5-5", output: Int = 100,
                       cacheRead: Int = 0, content: [[String: Any]] = [["type": "text", "text": "Done"]]) -> String {
        json([
            "type": "assistant", "timestamp": stamp(date), "requestId": "req_\(id)", "cwd": "/Users/demo/shop",
            "uuid": UUID().uuidString,
            "message": [
                "id": "msg_\(id)", "model": model, "content": content,
                "usage": ["input_tokens": 10, "output_tokens": output, "cache_read_input_tokens": cacheRead,
                          "cache_creation_input_tokens": 0],
            ],
        ])
    }

    private func prompt(_ text: String, at date: Date, uuid: String = UUID().uuidString) -> String {
        json(["type": "user", "timestamp": stamp(date), "uuid": uuid, "message": ["role": "user", "content": text]])
    }

    private func toolResult(at date: Date) -> String {
        json(["type": "user", "timestamp": stamp(date), "uuid": UUID().uuidString,
              "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "tu_1", "content": "ok"]]]])
    }

    private func files(in projects: Projects, cache: TranscriptScanner.Cache = [:]) throws -> TranscriptScanner.Cache {
        try TranscriptScanner.scan(root: projects.root, since: InsightsRange.earliestStart(now: now), cache: cache)
    }

    // MARK: Pricing

    @Test func pricesRepliesAtTheirModelsListPrice() throws {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        // Opus 5.5: $4 in, $20 out, $0.20 cache read, writes at 1.25× and 2× input.
        let expected: Double = 4 + 20 + 0.20 + 5 + 8
        let cost = try #require(ModelPricing.cost(of: usage, model: "claude-opus-5-5"))
        #expect(abs(cost - expected) < 0.000_001)
        // Fast mode doubles the token price.
        #expect(ModelPricing.cost(of: TokenUsage(output: 1_000_000), model: "claude-opus-5-5", isFast: true) == 40)
        // Older models read their cache at 0.1× input.
        let sonnetRead = ModelPricing.cost(of: TokenUsage(cacheRead: 1_000_000), model: "claude-sonnet-4-5-20250929") ?? 0
        #expect(abs(sonnetRead - 0.3) < 0.000_001)
    }

    @Test func picksTheMostSpecificModelID() {
        #expect(ModelPricing.rates(for: "claude-opus-4-5-20251101")?.input == 5)
        #expect(ModelPricing.rates(for: "claude-opus-4-1-20250805")?.input == 15)
        #expect(ModelPricing.rates(for: "claude-fable-5-1")?.cacheRead == 0.25)
        #expect(ModelPricing.rates(for: "gpt-something") == nil)
        #expect(ModelPricing.cost(of: TokenUsage(output: 10), model: "some-local-model") == nil)
    }

    @Test func haikuCostsMoreForLongPrompts() {
        let short = TokenUsage(input: 50_000)
        let long = TokenUsage(input: 150_000)
        #expect(ModelPricing.cost(of: short, model: "claude-haiku-5-5") == 50_000 * 0.10 / 1_000_000)
        #expect(ModelPricing.cost(of: long, model: "claude-haiku-5-5") == 150_000 * 0.50 / 1_000_000)
    }

    @Test func readsTheCacheWriteSplitFromUsage() {
        let tokens = TranscriptUsage.tokens(from: [
            "input_tokens": 3, "output_tokens": 7, "cache_read_input_tokens": 11, "cache_creation_input_tokens": 30,
            "cache_creation": ["ephemeral_5m_input_tokens": 10, "ephemeral_1h_input_tokens": 20],
            "server_tool_use": ["web_search_requests": 2],
        ])
        #expect(tokens == TokenUsage(input: 3, output: 7, cacheRead: 11, cacheWrite5m: 10, cacheWrite1h: 20, webSearches: 2))
        // Without the split, every write was a 5-minute one.
        #expect(TranscriptUsage.tokens(from: ["cache_creation_input_tokens": 40]).cacheWrite5m == 40)
    }

    // MARK: Reading transcripts

    @Test func countsEachReplyOnceAndOnlyTypedPrompts() throws {
        let projects = try Projects()
        let edit: [[String: Any]] = [["type": "tool_use", "name": "Edit", "input": ["file_path": "/shop/cart.swift"]]]
        try projects.write("-shop/s1.jsonl", lines: [
            prompt("Fix the cart total", at: now.addingTimeInterval(-600)),
            // One reply, written as two content-block lines with the same ids.
            reply(id: "a", at: now.addingTimeInterval(-590)),
            reply(id: "a", at: now.addingTimeInterval(-590), content: edit),
            toolResult(at: now.addingTimeInterval(-580)),
            reply(id: "b", at: now.addingTimeInterval(-570)),
            reply(id: "c", at: now.addingTimeInterval(-560), model: "<synthetic>"),
        ], modified: now)

        let file = try #require(try files(in: projects).values.first)
        #expect(file.replies.map(\.key) == ["msg_a:req_a", "msg_b:req_b"])
        #expect(file.prompts.count == 1)
        #expect(file.edits.map(\.path) == ["/shop/cart.swift"])
        #expect(file.project == "shop")
        #expect(file.sessionID == "s1")
    }

    @Test func readsOnlyNewLinesAfterTheFirstScan() throws {
        let projects = try Projects()
        let first = reply(id: "a", at: now.addingTimeInterval(-300))
        try projects.write("-shop/s1.jsonl", lines: [first], modified: now.addingTimeInterval(-200))
        // The scanner's URLs can differ from ours (/var vs /private/var); match by name.
        func session(_ cache: TranscriptScanner.Cache) -> TranscriptUsage? {
            cache.first { $0.key.lastPathComponent == "s1.jsonl" }?.value
        }
        let cache = try files(in: projects)
        #expect(session(cache)?.replies.count == 1)

        // A second reply, and a third still being written (no newline yet).
        try projects.write("-shop/s1.jsonl", lines: [first, reply(id: "b", at: now.addingTimeInterval(-100)), reply(id: "c", at: now)],
                           newlineAtEnd: false, modified: now.addingTimeInterval(-50))
        let next = try files(in: projects, cache: cache)
        #expect(session(next)?.replies.map(\.key) == ["msg_a:req_a", "msg_b:req_b"])
        #expect(session(next)?.readOffset ?? 0 > session(cache)?.readOffset ?? 0)

        try projects.write("-shop/s1.jsonl", lines: [first, reply(id: "b", at: now.addingTimeInterval(-100)), reply(id: "c", at: now)],
                           modified: now)
        #expect(session(try files(in: projects, cache: next))?.replies.count == 3)
    }

    @Test func findsSubagentsUnderTheirSessionAndSkipsOldFiles() throws {
        let projects = try Projects()
        try projects.write("-shop/s1.jsonl", lines: [reply(id: "a", at: now)], modified: now)
        try projects.write("-shop/s1/subagents/agent-1.jsonl", lines: [reply(id: "b", at: now)], modified: now)
        try projects.write("-shop/old.jsonl", lines: [reply(id: "c", at: now)], modified: now.addingTimeInterval(-400 * 86_400))

        let scanned: [TranscriptUsage] = try files(in: projects).values.sorted { !$0.isSubagent && $1.isSubagent }
        #expect(scanned.count == 2)
        #expect(scanned.map(\.sessionID) == ["s1", "s1"])
        #expect(scanned.map(\.isSubagent) == [false, true])
    }

    // MARK: Summaries

    private func ledger(_ session: String, project: String, replies: [(String, TimeInterval)], subagent: Bool = false) -> TranscriptUsage {
        var file = TranscriptUsage(sessionID: session, isSubagent: subagent)
        file.project = project
        file.replies = replies.map { key, ago in
            let tokens = TokenUsage(output: 1_000_000)
            return ReplyUsage(key: key, time: now.addingTimeInterval(-ago), family: .opus,
                              cost: ModelPricing.cost(of: tokens, model: "claude-opus-5-5"), tokens: tokens)
        }
        return file
    }

    @Test func aResumedSessionsCopiedRepliesCountOnce() {
        let original = ledger("s1", project: "shop", replies: [("r1", 3600), ("r2", 1800)])
        let resumed = ledger("s2", project: "shop", replies: [("r1", 3600), ("r2", 1800), ("r3", 60)])
        let summary = InsightsSummary.make(.day, from: [original, resumed], now: now)
        #expect(summary.replies == 3)
        #expect(summary.cost == 60)
        #expect(summary.projects.map(\.name) == ["shop"])
    }

    @Test func bucketsByHourForADayAndByDayForAMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let file = ledger("s1", project: "shop", replies: [("now", 60), ("2h", 2 * 3600 + 60), ("10d", 10 * 86_400), ("40d", 40 * 86_400)])

        let day = InsightsSummary.make(.day, from: [file], now: now, calendar: calendar)
        #expect(day.buckets.count == 24)
        #expect(day.replies == 2)
        #expect(day.buckets.last?.replies == 1)
        #expect(day.buckets[day.buckets.count - 3].replies == 1)

        let month = InsightsSummary.make(.month, from: [file], now: now, calendar: calendar)
        #expect(month.buckets.count == 30)
        #expect(month.replies == 3)
        #expect(month.buckets.last?.replies == 2)
    }

    @Test func bucketsByWeekForMonthsAndByMonthForAYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let file = ledger("s1", project: "shop", replies: [("now", 60), ("40d", 40 * 86_400), ("120d", 120 * 86_400), ("300d", 300 * 86_400), ("400d", 400 * 86_400)])

        let quarter = InsightsSummary.make(.quarter, from: [file], now: now, calendar: calendar)
        #expect(quarter.buckets.count == 13)
        #expect(quarter.replies == 2)
        #expect(quarter.buckets.last?.replies == 1)
        #expect(quarter.historyBegins == nil)

        let half = InsightsSummary.make(.half, from: [file], now: now, calendar: calendar)
        #expect(half.buckets.count == 26)
        #expect(half.replies == 3)

        let year = InsightsSummary.make(.year, from: [file], now: now, calendar: calendar)
        #expect(year.buckets.count == 12)
        #expect(year.replies == 4)
        #expect(year.buckets.last?.replies == 1)
        // Older history exists, so the average covers the whole year.
        #expect(year.historyBegins == nil)
        #expect(year.dayCount >= 334 && year.dayCount <= 366)
    }

    @Test func aLongRangeSpreadsItsAverageOverTheHistoryThatsLeft() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Claude Code kept 10 days of transcripts.
        let file = ledger("s1", project: "shop", replies: [("10d", 10 * 86_400), ("now", 60)])

        let year = InsightsSummary.make(.year, from: [file], now: now, calendar: calendar)
        #expect(year.historyBegins == now.addingTimeInterval(-10 * 86_400))
        #expect(year.dayCount == 11)

        // Short ranges keep their own length, even for someone new to Claude Code.
        let week = InsightsSummary.make(.week, from: [file], now: now, calendar: calendar)
        #expect(week.historyBegins == nil)
        #expect(week.dayCount == 7)
    }

    @Test func activeTimeAddsShortGapsAndSkipsSubagents() {
        // Gaps of 2 and 4 minutes count; the 20-minute break doesn't.
        let times = [0.0, 120, 360, 1560].map { now.addingTimeInterval($0) }
        #expect(InsightsSummary.activeTime(in: times) == 360)

        let main = ledger("s1", project: "shop", replies: [("a", 600), ("b", 480)])
        let helper = ledger("s1", project: "shop", replies: [("c", 590), ("d", 470)], subagent: true)
        let summary = InsightsSummary.make(.day, from: [main, helper], now: now)
        #expect(summary.activeTime == 120)
        #expect(summary.sessions == 1)
        #expect(summary.replies == 4)
    }

    @Test func formatsShortNumbers() {
        #expect(InsightsFormat.tokens(820) == "820")
        #expect(InsightsFormat.tokens(12_400) == "12.4K")
        #expect(InsightsFormat.tokens(63_800_000) == "63.8M")
        #expect(InsightsFormat.tokens(2_576_000_000) == "2.58B")
        #expect(InsightsFormat.duration(45 * 60) == "45m")
        #expect(InsightsFormat.duration(136 * 60) == "2h 16m")
        #expect(InsightsFormat.duration(59 * 3600) == "59h")
    }

    // MARK: Monitor

    @Test @MainActor func turningTheWidgetOffForgetsWhatItRead() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "insights-\(UUID())") ?? .standard)
        let monitor = InsightsMonitor(settings: settings, root: URL(fileURLWithPath: "/nonexistent"))
        monitor.showPreview([.day: InsightsSummary(range: .day, replies: 1)])
        #expect(monitor.summary(for: .day) != nil)
        monitor.setEnabled(false)
        #expect(!settings.insightsWidget)
        #expect(monitor.summary(for: .day) == nil)
    }
}
