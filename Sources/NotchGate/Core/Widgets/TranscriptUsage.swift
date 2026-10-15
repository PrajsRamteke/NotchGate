import Darwin
import Foundation
import NotchGateKit

/// One Claude reply's tokens. Claude Code writes a transcript line per content
/// block, each repeating the reply's usage, so replies are keyed by message
/// and request id and counted once.
struct ReplyUsage: Equatable, Sendable {
    let key: String
    let time: Date
    let family: ModelFamily
    /// At API prices; `nil` for a model without a list price.
    let cost: Double?
    let tokens: TokenUsage
}

/// A prompt the person typed, keyed so a resumed session's copy isn't counted twice.
struct PromptMark: Equatable, Sendable {
    let key: String
    let time: Date
}

/// A file Claude edited or wrote.
struct FileEdit: Equatable, Sendable {
    let time: Date
    let path: String
}

/// What one transcript says about usage, and how far it has been read.
/// Transcripts only grow, so a later scan reads just the new lines.
struct TranscriptUsage: Sendable {
    /// The Claude Code session this file belongs to (a subagent's parent session).
    let sessionID: String
    /// Subagent transcripts cost tokens but overlap their parent's time.
    let isSubagent: Bool
    /// Folder name of the session's working directory.
    var project: String?
    var replies: [ReplyUsage] = []
    var prompts: [PromptMark] = []
    var edits: [FileEdit] = []

    /// Bytes read so far: always the end of a complete line.
    var readOffset: UInt64 = 0
    /// File size and date at the last read; an unchanged file isn't opened again.
    var size: UInt64 = 0
    var modified: Date = .distantPast

    private var replyIndex: [String: Int] = [:]

    init(sessionID: String, isSubagent: Bool) {
        self.sessionID = sessionID
        self.isSubagent = isSubagent
    }

    /// Lines longer than this hold tool output or images, never a typed prompt.
    static let maxPromptLineBytes = 64 * 1024
    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    private static let assistantMarker = Array(#""type":"assistant""#.utf8)
    private static let userMarker = Array(#""type":"user""#.utf8)
    /// User lines carrying tool output, never something typed.
    private static let toolResultMarker = Array(#""tool_use_id""#.utf8)

    // MARK: Reading

    /// Reads the lines added since `previous` was read, or the whole file when
    /// it's new, shrank or was replaced.
    static func read(_ url: URL, size: UInt64, modified: Date, previous: TranscriptUsage?, sessionID: String, isSubagent: Bool) -> TranscriptUsage {
        var usage: TranscriptUsage
        if let previous, size >= previous.readOffset, modified >= previous.modified {
            usage = previous
        } else {
            usage = TranscriptUsage(sessionID: sessionID, isSubagent: isSubagent)
        }
        usage.size = size
        usage.modified = modified
        // Mapped, not copied: only the lines that matter are ever copied out.
        guard size > usage.readOffset, let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return usage }
        let unread = data.dropFirst(Int(usage.readOffset))
        // A last line without its newline is still being written; it's read next time.
        guard let lastNewline = unread.lastIndex(of: newline) else { return usage }
        usage.ingest(Data(unread[unread.startIndex..<lastNewline]))
        usage.readOffset = UInt64(lastNewline + 1)
        return usage
    }

    private static let newline = UInt8(ascii: "\n")

    /// Every complete line in `data` (no trailing partial line).
    ///
    /// Most of a transcript is tool output, so lines are sorted with `memchr` /
    /// `memmem` on the raw bytes and only replies and short user lines are decoded.
    mutating func ingest(_ data: Data) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var start = 0
            while start < raw.count {
                let end = memchr(base + start, Int32(Self.newline), raw.count - start)
                    .map { base.distance(to: UnsafeRawPointer($0)) } ?? raw.count
                if end > start { ingestLine(base + start, count: end - start) }
                start = end + 1
            }
        }
    }

    private mutating func ingestLine(_ bytes: UnsafeRawPointer, count: Int) {
        func contains(_ marker: [UInt8]) -> Bool {
            marker.withUnsafeBytes { memmem(bytes, count, $0.baseAddress, marker.count) != nil }
        }
        // The marker can also sit inside a message's text, so the decoded type decides.
        if contains(Self.assistantMarker), ingestReply(Data(bytes: bytes, count: count)) { return }
        guard count <= Self.maxPromptLineBytes, contains(Self.userMarker),
              !contains(Self.toolResultMarker) else { return }
        ingestPrompt(Data(bytes: bytes, count: count))
    }

    // MARK: Lines

    /// - Returns: whether the line was a reply.
    @discardableResult
    private mutating func ingestReply(_ line: Data) -> Bool {
        guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              entry["type"] as? String == "assistant",
              let message = entry["message"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let usageJSON = message["usage"] as? [String: Any],
              let time = (entry["timestamp"] as? String).flatMap(Self.date)
        else { return false }

        if project == nil, let cwd = entry["cwd"] as? String, !cwd.isEmpty {
            project = URL(fileURLWithPath: cwd).lastPathComponent
        }

        let tokens = Self.tokens(from: usageJSON)
        let isFast = usageJSON["speed"] as? String == "fast"
        let id = message["id"] as? String ?? entry["uuid"] as? String ?? UUID().uuidString
        let key = "\(id):\(entry["requestId"] as? String ?? "")"
        let reply = ReplyUsage(
            key: key, time: time, family: ModelFamily(model: model),
            cost: ModelPricing.cost(of: tokens, model: model, isFast: isFast), tokens: tokens
        )
        if let index = replyIndex[key] {
            // The same reply again (another content block): keep the fuller count.
            if tokens.output > replies[index].tokens.output { replies[index] = reply }
        } else {
            replyIndex[key] = replies.count
            replies.append(reply)
        }

        for block in message["content"] as? [[String: Any]] ?? [] {
            guard block["type"] as? String == "tool_use",
                  let name = block["name"] as? String, Self.editTools.contains(name),
                  let input = block["input"] as? [String: Any],
                  let path = (input["file_path"] ?? input["notebook_path"]) as? String, !path.isEmpty
            else { continue }
            edits.append(FileEdit(time: time, path: path))
        }
        return true
    }

    private mutating func ingestPrompt(_ line: Data) {
        guard let entry = try? JSONDecoder().decode(JSONValue.self, from: line),
              entry["type"]?.stringValue == "user",
              entry["isSidechain"]?.boolValue != true,
              SessionHistory.promptText(entry) != nil,
              let time = entry["timestamp"]?.stringValue.flatMap(Self.date)
        else { return }
        let key = entry["uuid"]?.stringValue ?? "\(sessionID):\(time.timeIntervalSince1970)"
        prompts.append(PromptMark(key: key, time: time))
    }

    static func tokens(from usage: [String: Any]) -> TokenUsage {
        func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let creation = int(usage["cache_creation_input_tokens"])
        var write5m = creation, write1h = 0
        if let split = usage["cache_creation"] as? [String: Any] {
            write1h = int(split["ephemeral_1h_input_tokens"])
            write5m = int(split["ephemeral_5m_input_tokens"])
            // Older entries only have the total; whatever the split doesn't cover was 5-minute.
            if write5m + write1h < creation { write5m = creation - write1h }
        }
        return TokenUsage(
            input: int(usage["input_tokens"]),
            output: int(usage["output_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            cacheWrite5m: write5m,
            cacheWrite1h: write1h,
            webSearches: int((usage["server_tool_use"] as? [String: Any])?["web_search_requests"])
        )
    }

    /// Transcript timestamps: ISO 8601 in UTC, usually with milliseconds.
    static func date(_ string: String) -> Date? {
        (try? Date(string, strategy: fractionalFormat)) ?? (try? Date(string, strategy: plainFormat))
    }

    private static let fractionalFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainFormat = Date.ISO8601FormatStyle()
}

/// Finds and reads the transcripts under `~/.claude/projects` changed in the
/// last `window`, reusing what earlier scans read. Runs off the main thread.
enum TranscriptScanner {
    typealias Cache = [URL: TranscriptUsage]

    /// - Returns: every transcript touched since `since`; that is also the cache for the next scan.
    static func scan(
        root: URL = SessionHistory.projectsDirectory,
        since: Date,
        cache: Cache,
        fileManager: FileManager = .default
    ) throws(SessionHistory.ScanError) -> Cache {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [:] }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        let projects: [URL]
        do {
            projects = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        } catch {
            throw .unreadable(root.path)
        }

        // Find what changed first, then read those files in parallel.
        var next: Cache = [:]
        var toRead: [(url: URL, size: UInt64, modified: Date, sessionID: String, isSubagent: Bool)] = []
        func visit(_ file: URL, sessionID: String, isSubagent: Bool) {
            guard file.pathExtension == "jsonl",
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified >= since
            else { return }
            let size = UInt64(values.fileSize ?? 0)
            if let cached = cache[file], cached.size == size, cached.modified == modified {
                next[file] = cached
            } else {
                toRead.append((file, size, modified, sessionID, isSubagent))
            }
        }

        for project in projects where isFolder(project) {
            let entries = (try? fileManager.contentsOfDirectory(at: project, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
            for entry in entries {
                if isFolder(entry) {
                    // `<session id>/subagents/agent-….jsonl`: a subagent of that session.
                    let subagents = entry.appendingPathComponent("subagents", isDirectory: true)
                    let files = (try? fileManager.contentsOfDirectory(at: subagents, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
                    for file in files { visit(file, sessionID: entry.lastPathComponent, isSubagent: true) }
                } else {
                    visit(entry, sessionID: entry.deletingPathExtension().lastPathComponent, isSubagent: false)
                }
            }
        }

        let read = readInParallel(toRead.map { item in
            { TranscriptUsage.read(item.url, size: item.size, modified: item.modified, previous: cache[item.url],
                                   sessionID: item.sessionID, isSubagent: item.isSubagent) }
        })
        for (item, usage) in zip(toRead, read) { next[item.url] = usage }
        return next
    }

    /// Half the cores at most: a first scan finishes quickly without
    /// crowding out everything else on the Mac.
    static var workerCount: Int { max(1, ProcessInfo.processInfo.activeProcessorCount / 2) }

    /// Runs `jobs` on `workerCount` threads; results in the jobs' order.
    private static func readInParallel(_ jobs: [@Sendable () -> TranscriptUsage]) -> [TranscriptUsage] {
        guard jobs.count > 1 else { return jobs.map { $0() } }
        let results = ResultSlots(count: jobs.count)
        let workers = min(workerCount, jobs.count)
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: jobs.count, by: workers) {
                results.set(jobs[index](), at: index)
            }
        }
        return results.values
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// Fixed slots the parallel readers fill, each written by exactly one worker.
private final class ResultSlots: @unchecked Sendable {
    private var slots: [TranscriptUsage?]
    private let lock = NSLock()

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ value: TranscriptUsage, at index: Int) {
        lock.lock()
        slots[index] = value
        lock.unlock()
    }

    var values: [TranscriptUsage] {
        lock.lock()
        defer { lock.unlock() }
        return slots.map { $0! }
    }
}
