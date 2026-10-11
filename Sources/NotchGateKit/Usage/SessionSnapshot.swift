import Foundation

/// One Claude Code session as its status line sees it: model, how full the
/// context window is, what it has cost so far, and the git branch.
///
/// The hook's status line relay writes one file per session into
/// `BridgeLocation.sessionsDirectory`, so sessions running side by side don't
/// overwrite each other; the app's Session widget reads them from there.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    /// Claude Code's `session_id`, the same id its hooks report.
    public var sessionID: String
    /// The session's project directory.
    public var directory: String?
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
        sessionID: String,
        directory: String? = nil,
        model: String?,
        contextPercent: Double?,
        contextSize: Int?,
        costUSD: Double?,
        branch: String?,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.directory = directory
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
        guard let sessionID = input["session_id"]?.stringValue, !sessionID.isEmpty else { return nil }
        let context = input["context_window"]
        self.init(
            sessionID: sessionID,
            directory: Self.directory(in: input),
            model: input["model"]?["display_name"]?.stringValue,
            contextPercent: context?["used_percentage"]?.doubleValue.map { min(max($0, 0), 100) },
            contextSize: context?["context_window_size"]?.doubleValue.flatMap { Int(exactly: $0.rounded()) },
            costUSD: input["cost"]?["total_cost_usd"]?.doubleValue,
            branch: branch,
            updatedAt: now
        )
    }

    /// The project directory from status line input, falling back to the working directory.
    public static func directory(in input: JSONValue) -> String? {
        let workspace = input["workspace"]
        return [workspace?["project_dir"], workspace?["current_dir"], input["cwd"]]
            .lazy
            .compactMap { $0?.stringValue }
            .first { !$0.isEmpty }
    }

    /// Folder name of the project, such as "NotchGate".
    public var projectName: String? {
        directory.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    // MARK: Persistence

    /// This session's file in `directory`. The id is reduced to safe characters
    /// so it can't point outside the folder.
    public static func fileURL(for sessionID: String, in directory: URL = BridgeLocation.sessionsDirectory) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = String(String.UnicodeScalarView(sessionID.unicodeScalars.filter(allowed.contains)))
        return directory.appendingPathComponent((safe.isEmpty ? "session" : safe) + ".json")
    }

    public static func load(from url: URL) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    /// Writes this session's file into `directory`, replacing its previous one.
    public func save(in directory: URL = BridgeLocation.sessionsDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL(for: sessionID, in: directory), options: .atomic)
    }
}
