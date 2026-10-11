import Foundation

/// The latest Claude Code session as its status line sees it: model, how full
/// the context window is, what it has cost so far, and the git branch.
///
/// The hook's status line relay writes the most recent one to
/// `BridgeLocation.sessionURL`; the app's Session widget reads it from there.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    /// Model display name, such as "Opus".
    public var model: String?
    /// 0–100, how full the context window is.
    public var contextPercent: Double?
    /// Size of the context window in tokens, such as 200 000.
    public var contextSize: Int?
    /// Estimated session cost in US dollars.
    public var costUSD: Double?
    /// Current git branch of the session's directory, `nil` outside a repo or on a detached HEAD.
    public var branch: String?
    /// When the status line last reported this session.
    public var updatedAt: Date

    public init(
        model: String?,
        contextPercent: Double?,
        contextSize: Int?,
        costUSD: Double?,
        branch: String?,
        updatedAt: Date
    ) {
        self.model = model
        self.contextPercent = contextPercent
        self.contextSize = contextSize
        self.costUSD = costUSD
        self.branch = branch
        self.updatedAt = updatedAt
    }

    /// Reads Claude Code's status line input. The branch comes from the caller,
    /// because the status line input does not include it.
    ///
    /// - Returns: `nil` when the input has no `session_id`.
    public init?(statusLine input: JSONValue, branch: String?, now: Date = Date()) {
        guard input["session_id"]?.stringValue != nil else { return nil }
        let context = input["context_window"]
        self.init(
            model: input["model"]?["display_name"]?.stringValue,
            contextPercent: context?["used_percentage"]?.doubleValue.map { min(max($0, 0), 100) },
            contextSize: context?["context_window_size"]?.doubleValue.flatMap { Int(exactly: $0.rounded()) },
            costUSD: input["cost"]?["total_cost_usd"]?.doubleValue,
            branch: branch,
            updatedAt: now
        )
    }

    // MARK: Persistence

    public static func load(from url: URL = BridgeLocation.sessionURL) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    public func save(to url: URL = BridgeLocation.sessionURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
