import Foundation

/// The claude.ai plan limits Claude Code reports to its status line
/// (`rate_limits` in the status line JSON). Only Pro and Max subscribers get
/// them, and only after a session's first reply.
///
/// The hook writes the latest snapshot to `BridgeLocation.usageURL`; the app
/// reads it from there, so the numbers survive app restarts.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        /// 0–100.
        public var usedPercentage: Double
        public var resetsAt: Date

        public init(usedPercentage: Double, resetsAt: Date) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }

        /// Claude Code drops a window once it resets; a stale file can still hold it.
        public func hasReset(at now: Date) -> Bool { resetsAt <= now }
    }

    /// The rolling 5-hour session limit.
    public var fiveHour: Window?
    /// The weekly limit.
    public var sevenDay: Window?
    /// When Claude Code last reported these numbers.
    public var updatedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    /// Reads `rate_limits` from Claude Code's status line input.
    ///
    /// - Returns: `nil` when the input has no `rate_limits` at all (API-key
    ///   users, or before the session's first reply). A missing window inside
    ///   it means that window has reset.
    public init?(statusLine input: JSONValue, now: Date = Date()) {
        guard let limits = input["rate_limits"], limits.objectValue != nil else { return nil }
        self.init(
            fiveHour: Self.window(limits["five_hour"]),
            sevenDay: Self.window(limits["seven_day"]),
            updatedAt: now
        )
    }

    private static func window(_ value: JSONValue?) -> Window? {
        guard let used = value?["used_percentage"]?.doubleValue,
              let resets = value?["resets_at"]?.doubleValue else { return nil }
        return Window(usedPercentage: min(max(used, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
    }

    // MARK: Persistence

    public static func load(from url: URL = BridgeLocation.usageURL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public func save(to url: URL = BridgeLocation.usageURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
