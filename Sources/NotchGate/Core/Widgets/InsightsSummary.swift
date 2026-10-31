import Foundation

/// The span the Insights card covers.
enum InsightsRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter, half, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .month: return "30d"
        case .quarter: return "3m"
        case .half: return "6m"
        case .year: return "1y"
        }
    }

    var spoken: String {
        switch self {
        case .day: return "last 24 hours"
        case .week: return "last 7 days"
        case .month: return "last 30 days"
        case .quarter: return "last 3 months"
        case .half: return "last 6 months"
        case .year: return "last 12 months"
        }
    }

    /// Bars in the chart: hours for a day, days for a week or a month, weeks
    /// for 3 or 6 months, months for a year.
    var bucketCount: Int {
        switch self {
        case .day: return 24
        case .week: return 7
        case .month: return 30
        case .quarter: return 13
        case .half: return 26
        case .year: return 12
        }
    }

    var bucketComponent: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .quarter, .half: return .weekOfYear
        case .year: return .month
        }
    }

    /// Longer than Claude Code keeps transcripts by default (30 days).
    var outlastsDefaultHistory: Bool { bucketComponent == .weekOfYear || bucketComponent == .month }

    /// The first bar's start: the hour 23 hours ago, midnight 6 / 29 days ago,
    /// the start of the week 12 / 25 weeks ago, or the first of the month 11 months ago.
    func start(now: Date, calendar: Calendar) -> Date {
        let current = calendar.dateInterval(of: bucketComponent, for: now)?.start ?? now
        return calendar.date(byAdding: bucketComponent, value: -(bucketCount - 1), to: current) ?? current
    }

    /// How far back transcripts are read to cover every range.
    static func earliestStart(now: Date, calendar: Calendar = .current) -> Date {
        allCases.map { $0.start(now: now, calendar: calendar) }.min() ?? now
    }
}

/// Claude Code usage over one range: totals, a bar per hour or day, and where
/// the tokens went.
struct InsightsSummary: Equatable, Sendable {
    struct Bucket: Equatable, Sendable, Identifiable {
        let start: Date
        var cost: Double = 0
        var tokens = 0
        var replies = 0
        var id: Date { start }
    }

    struct Share: Equatable, Sendable {
        let name: String
        let cost: Double
        let tokens: Int
    }

    let range: InsightsRange
    var cost: Double = 0
    /// Some replies came from a model without a list price; their tokens count, their cost doesn't.
    var hasUnpricedReplies = false
    var tokens = TokenUsage()
    var replies = 0
    var sessions = 0
    var prompts = 0
    var filesChanged = 0
    /// Time Claude was working: gaps of up to five minutes between a session's prompts and replies.
    var activeTime: TimeInterval = 0
    var buckets: [Bucket] = []
    /// Most expensive first.
    var projects: [Share] = []
    var models: [Share] = []
    /// Days the per-day average is spread over: the whole range, or only the
    /// part Claude Code still has transcripts for.
    var dayCount = 1
    /// For a range longer than Claude Code's default 30 days of history: when
    /// the oldest transcript still on disk begins, if that's after the range starts.
    var historyBegins: Date?

    var isEmpty: Bool { replies == 0 && prompts == 0 }

    /// Share of the prompt read from the cache: the higher, the cheaper.
    var cacheHitRate: Double? {
        tokens.prompt > 0 ? Double(tokens.cacheRead) / Double(tokens.prompt) : nil
    }

    var peakBucket: Bucket? { buckets.max { $0.cost < $1.cost } }

    /// Gaps longer than this between a session's messages are someone away, not Claude working.
    static let activeGap: TimeInterval = 5 * 60

    /// Adds up `files` over `range`. A reply or prompt that appears in two
    /// transcripts (a resumed session copies its history) counts once.
    static func make(
        _ range: InsightsRange,
        from files: some Collection<TranscriptUsage>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> InsightsSummary {
        var summary = InsightsSummary(range: range)
        let start = range.start(now: now, calendar: calendar)
        summary.buckets = (0..<range.bucketCount).compactMap { offset in
            calendar.date(byAdding: range.bucketComponent, value: offset, to: start).map { Bucket(start: $0) }
        }
        let bucketStarts = summary.buckets.map(\.start)

        let oldest = files.compactMap { file in
            [file.replies.lazy.map(\.time).min(), file.prompts.lazy.map(\.time).min()].compactMap { $0 }.min()
        }.min()
        var covered = start
        if range.outlastsDefaultHistory, let oldest, oldest > start {
            summary.historyBegins = oldest
            covered = calendar.startOfDay(for: oldest)
        }
        summary.dayCount = max(1, Int((now.timeIntervalSince(covered) / 86_400).rounded(.up)))

        var seenReplies = Set<String>(), seenPrompts = Set<String>()
        var sessions = Set<String>(), changed = Set<String>()
        var projectCost: [String: (cost: Double, tokens: Int)] = [:]
        var modelCost: [ModelFamily: (cost: Double, tokens: Int)] = [:]

        // Stable order, so which copy of a duplicate wins doesn't change between scans.
        for file in files.sorted(by: { $0.modified < $1.modified }) {
            var times: [Date] = []
            for reply in file.replies where reply.time >= start && reply.time <= now {
                guard seenReplies.insert(reply.key).inserted else { continue }
                let cost = reply.cost ?? 0
                if reply.cost == nil { summary.hasUnpricedReplies = true }
                summary.cost += cost
                summary.tokens += reply.tokens
                summary.replies += 1
                sessions.insert(file.sessionID)
                let index = bucketIndex(for: reply.time, in: bucketStarts)
                summary.buckets[index].cost += cost
                summary.buckets[index].tokens += reply.tokens.total
                summary.buckets[index].replies += 1
                let project = file.project ?? "Other"
                projectCost[project, default: (0, 0)].cost += cost
                projectCost[project, default: (0, 0)].tokens += reply.tokens.total
                modelCost[reply.family, default: (0, 0)].cost += cost
                modelCost[reply.family, default: (0, 0)].tokens += reply.tokens.total
                times.append(reply.time)
            }
            for prompt in file.prompts where prompt.time >= start && prompt.time <= now {
                guard seenPrompts.insert(prompt.key).inserted else { continue }
                summary.prompts += 1
                sessions.insert(file.sessionID)
                times.append(prompt.time)
            }
            for edit in file.edits where edit.time >= start && edit.time <= now {
                changed.insert(edit.path)
            }
            // A subagent works while its parent waits; counting both would double the time.
            if !file.isSubagent { summary.activeTime += activeTime(in: times) }
        }

        summary.sessions = sessions.count
        summary.filesChanged = changed.count
        summary.projects = projectCost
            .map { Share(name: $0.key, cost: $0.value.cost, tokens: $0.value.tokens) }
            .sorted { ($0.cost, $0.tokens) > ($1.cost, $1.tokens) }
        summary.models = modelCost
            .map { Share(name: $0.key.title, cost: $0.value.cost, tokens: $0.value.tokens) }
            .sorted { ($0.cost, $0.tokens) > ($1.cost, $1.tokens) }
        return summary
    }

    /// Sum of the gaps of at most `activeGap` between consecutive messages.
    static func activeTime(in times: [Date]) -> TimeInterval {
        let sorted = times.sorted()
        return zip(sorted, sorted.dropFirst()).reduce(0) { total, pair in
            let gap = pair.1.timeIntervalSince(pair.0)
            return gap <= activeGap ? total + gap : total
        }
    }

    /// The last bucket starting at or before `time`.
    private static func bucketIndex(for time: Date, in starts: [Date]) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
