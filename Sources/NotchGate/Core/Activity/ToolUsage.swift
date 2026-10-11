import Foundation

/// Which tools a session has called, and when: the numbers behind the Tools widget.
///
/// Counts cover the whole session (a compaction keeps them, a new or resumed
/// session starts over). Calls are also kept per minute for the last hour, for
/// the widget's activity strip.
struct ToolUsage: Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case run, edit, read, search, web, agent, mcp, other

        init(toolName: String) {
            switch toolName {
            case "Bash", "BashOutput", "KillShell", "KillBash": self = .run
            case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .edit
            case "Read", "NotebookRead": self = .read
            case "Grep", "Glob", "LS", "ToolSearch": self = .search
            case "WebFetch", "WebSearch": self = .web
            case "Agent", "Task": self = .agent
            case let name where name.hasPrefix("mcp__"): self = .mcp
            default: self = .other
            }
        }

        var title: String {
            switch self {
            case .run: return "Bash"
            case .edit: return "Edit"
            case .read: return "Read"
            case .search: return "Search"
            case .web: return "Web"
            case .agent: return "Agents"
            case .mcp: return "MCP"
            case .other: return "Other"
            }
        }

        var symbol: String {
            switch self {
            case .run: return "terminal"
            case .edit: return "pencil"
            case .read: return "doc.text"
            case .search: return "magnifyingglass"
            case .web: return "globe"
            case .agent: return "person.2"
            case .mcp: return "puzzlepiece.extension"
            case .other: return "wrench.and.screwdriver"
            }
        }
    }

    private(set) var counts: [Category: Int] = [:]
    /// Calls per minute, keyed by minutes since 1970, for the last `history` minutes.
    private(set) var minutes: [Int: Int] = [:]
    private(set) var lastCallAt: Date?

    /// Minutes of per-minute history kept.
    static let history = 60

    var total: Int { counts.values.reduce(0, +) }
    var isEmpty: Bool { total == 0 }

    func count(_ category: Category) -> Int { counts[category] ?? 0 }

    /// Categories that were used, most calls first (ties in `allCases` order).
    var ranked: [(category: Category, count: Int)] {
        Category.allCases
            .map { ($0, count($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    mutating func record(toolName: String, at date: Date) {
        counts[Category(toolName: toolName), default: 0] += 1
        let minute = Self.minute(of: date)
        minutes[minute, default: 0] += 1
        minutes = minutes.filter { $0.key > minute - Self.history }
        if lastCallAt.map({ date > $0 }) ?? true { lastCallAt = date }
    }

    /// Calls in each of the last `buckets` spans of `bucketMinutes`, oldest first,
    /// the last one ending with the minute of `now`.
    func timeline(endingAt now: Date, buckets: Int = 30, bucketMinutes: Int = 2) -> [Int] {
        guard buckets > 0, bucketMinutes > 0 else { return [] }
        let current = Self.minute(of: now)
        return (0..<buckets).map { bucket in
            let end = current - (buckets - 1 - bucket) * bucketMinutes
            return ((end - bucketMinutes + 1)...end).reduce(0) { $0 + (minutes[$1] ?? 0) }
        }
    }

    /// Several sessions' usage added together.
    static func combined<S: Sequence>(_ usages: S) -> ToolUsage where S.Element == ToolUsage {
        usages.reduce(into: ToolUsage()) { sum, usage in
            sum.counts.merge(usage.counts, uniquingKeysWith: +)
            sum.minutes.merge(usage.minutes, uniquingKeysWith: +)
            if let last = usage.lastCallAt, sum.lastCallAt.map({ last > $0 }) ?? true { sum.lastCallAt = last }
        }
    }

    private static func minute(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }
}
