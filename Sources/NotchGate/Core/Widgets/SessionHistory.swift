import Foundation
import NotchGateKit

/// A Claude Code session that can be picked up again with `claude --resume`.
struct PastSession: Identifiable, Equatable, Sendable {
    /// Claude Code's session id (the transcript's file name).
    let id: String
    /// Where the session ran; `claude --resume` only finds it from there.
    let directory: String
    /// The session's title: the one it was renamed to, Claude's own, or its first prompt.
    let title: String
    let branch: String?
    /// When the transcript last changed.
    let updatedAt: Date

    var projectName: String { URL(fileURLWithPath: directory).lastPathComponent }
}

/// Finds recent sessions in Claude Code's transcripts
/// (`~/.claude/projects/<project>/<session id>.jsonl`, one JSON object per line).
///
/// Transcripts run to megabytes, mostly tool output, so only the start and
/// the end of each are read. Everything here runs off the main thread.
enum SessionHistory {
    enum ScanError: LocalizedError, Equatable {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let path): return "Couldn't read \(path)."
            }
        }
    }

    /// What one transcript says about its session; `nil` fields weren't found.
    struct Details: Equatable, Sendable {
        var directory: String?
        var branch: String?
        var customTitle: String?
        var aiTitle: String?
        var firstPrompt: String?
        /// Started by an Agent SDK program rather than a person; not worth resuming.
        var isAutomated = false
        /// At least one real exchange; sessions opened and quit have none.
        var hasConversation = false

        var title: String? { customTitle ?? aiTitle ?? firstPrompt }

        /// Combines what the end of a transcript said (`self`) with what its
        /// start said: the latest values win, except the prompt, which is the first.
        func merged(withEarlier earlier: Details) -> Details {
            Details(
                directory: directory ?? earlier.directory,
                branch: branch ?? earlier.branch,
                customTitle: customTitle ?? earlier.customTitle,
                aiTitle: aiTitle ?? earlier.aiTitle,
                firstPrompt: earlier.firstPrompt ?? firstPrompt,
                isAutomated: isAutomated || earlier.isAutomated,
                hasConversation: hasConversation || earlier.hasConversation
            )
        }
    }

    /// Parsed transcripts by file, with the modification date they were read at.
    /// `nil`: the transcript was read and isn't resumable.
    typealias Cache = [URL: (modified: Date, session: PastSession?)]

    static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Bytes read from each end of a transcript.
    static let headBytes = 2 * 1024 * 1024
    static let tailBytes = 1024 * 1024
    /// Lines longer than this are tool output or images; they're skipped without decoding.
    static let maxLineBytes = 256 * 1024

    /// The `limit` most recently active resumable sessions, newest first.
    ///
    /// - Parameters:
    ///   - excluding: ids of sessions that are running right now.
    ///   - cache: transcripts read by earlier scans; unchanged ones aren't read again.
    /// - Returns: the sessions, and the cache to pass to the next scan.
    /// - Throws: `ScanError.unreadable` when `root` exists but can't be listed.
    ///   A missing `root` (Claude Code never ran) is no sessions, not an error.
    static func recent(
        in root: URL = projectsDirectory,
        limit: Int,
        excluding: Set<String> = [],
        cache: Cache = [:],
        fileManager: FileManager = .default
    ) throws(ScanError) -> (sessions: [PastSession], cache: Cache) {
        guard limit > 0 else { return ([], cache) }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ([], [:])
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let projects: [URL]
        do {
            projects = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        } catch {
            throw .unreadable(root.path)
        }

        // Subagent transcripts live in subfolders; only top-level files are sessions.
        var candidates: [(url: URL, modified: Date)] = []
        for project in projects where (try? project.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let files = (try? fileManager.contentsOfDirectory(
                at: project, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
            )) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard !excluding.contains(file.deletingPathExtension().lastPathComponent),
                      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                else { continue }
                candidates.append((file, modified))
            }
        }
        candidates.sort { $0.modified > $1.modified }

        var sessions: [PastSession] = []
        var nextCache: Cache = [:]
        // Empty sessions are skipped, so look a little past `limit`, but not through everything.
        for candidate in candidates.prefix(max(limit * 8, 24)) {
            let session: PastSession?
            if let cached = cache[candidate.url], cached.modified == candidate.modified {
                session = cached.session
            } else {
                session = read(candidate.url, modified: candidate.modified)
            }
            nextCache[candidate.url] = (candidate.modified, session)
            if let session {
                sessions.append(session)
                if sessions.count == limit { break }
            }
        }
        return (sessions, nextCache)
    }

    /// The session in one transcript, or `nil` if it can't or shouldn't be resumed.
    static func read(_ url: URL, modified: Date) -> PastSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        // The end has the latest title and branch; the start has the first prompt.
        let tailStart = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        var details = chunk(of: handle, from: tailStart, count: Int(size - tailStart))
            .map { scan(lines(in: $0, startsMidLine: tailStart > 0, endsMidLine: false)) } ?? Details()
        // Without a title, the session goes by its first prompt, which only the start has.
        let needsStart = (details.customTitle == nil && details.aiTitle == nil) || details.directory == nil || !details.hasConversation
        if tailStart > 0, needsStart, let head = chunk(of: handle, from: 0, count: Int(min(size, UInt64(headBytes)))) {
            details = details.merged(withEarlier: scan(lines(in: head, startsMidLine: false, endsMidLine: size > UInt64(headBytes))))
        }
        return session(id: url.deletingPathExtension().lastPathComponent, details: details, modified: modified)
    }

    /// Builds the session from what its transcript said.
    static func session(id: String, details: Details, modified: Date) -> PastSession? {
        guard !id.isEmpty, !details.isAutomated, details.hasConversation,
              let directory = details.directory, !directory.isEmpty else { return nil }
        return PastSession(
            id: id,
            directory: directory,
            title: details.title.map(tidy) ?? "Untitled session",
            branch: details.branch,
            updatedAt: modified
        )
    }

    /// Reads transcript lines, in file order: titles, directory and branch end
    /// up as the latest ones, the prompt as the first.
    static func scan<S: Sequence>(_ lines: S) -> Details where S.Element == Data {
        var details = Details()
        let decoder = JSONDecoder()
        for line in lines where line.count <= maxLineBytes {
            guard let entry = try? decoder.decode(JSONValue.self, from: line) else { continue }
            let type = entry["type"]?.stringValue
            switch type {
            case "custom-title":
                details.customTitle = nonEmpty(entry["customTitle"]?.stringValue ?? entry["title"]?.stringValue)
                    ?? details.customTitle
            case "ai-title":
                details.aiTitle = nonEmpty(entry["aiTitle"]?.stringValue) ?? details.aiTitle
            case "summary":
                // Older Claude Code versions title sessions this way.
                details.aiTitle = nonEmpty(entry["summary"]?.stringValue) ?? details.aiTitle
            case "user", "assistant":
                guard entry["isSidechain"]?.boolValue != true else { continue }
                if entry["entrypoint"]?.stringValue?.hasPrefix("sdk") == true { details.isAutomated = true }
                details.directory = nonEmpty(entry["cwd"]?.stringValue) ?? details.directory
                // A detached HEAD reports "HEAD", which isn't a branch to show.
                if let branch = nonEmpty(entry["gitBranch"]?.stringValue), branch != "HEAD" { details.branch = branch }
                if type == "assistant" {
                    details.hasConversation = true
                } else if let prompt = promptText(entry) {
                    details.hasConversation = true
                    if details.firstPrompt == nil { details.firstPrompt = prompt }
                }
            default:
                continue
            }
        }
        return details
    }

    /// What the person typed, skipping tool results, slash-command echoes and other generated text.
    static func promptText(_ entry: JSONValue) -> String? {
        guard entry["isMeta"]?.boolValue != true, entry["isCompactSummary"]?.boolValue != true else { return nil }
        let content = entry["message"]?["content"]
        let text: String?
        if let string = content?.stringValue {
            text = string
        } else {
            text = content?.arrayValue?
                .first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
        }
        guard let text = nonEmpty(text), !text.hasPrefix("<"), !text.hasPrefix("Caveat:") else { return nil }
        return text
    }

    /// One line, at most 120 characters.
    static func tidy(_ title: String) -> String {
        let line = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? title
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(119)) + "…" : collapsed
    }

    // MARK: Reading

    private static func chunk(of handle: FileHandle, from offset: UInt64, count: Int) -> Data? {
        guard count > 0, (try? handle.seek(toOffset: offset)) != nil else { return nil }
        return try? handle.read(upToCount: count)
    }

    /// Splits on newlines, dropping a partial first or last line.
    static func lines(in data: Data, startsMidLine: Bool, endsMidLine: Bool) -> [Data] {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if startsMidLine, !lines.isEmpty { lines.removeFirst() }
        if endsMidLine, !lines.isEmpty { lines.removeLast() }
        return lines.filter { !$0.isEmpty }.map { Data($0) }
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
