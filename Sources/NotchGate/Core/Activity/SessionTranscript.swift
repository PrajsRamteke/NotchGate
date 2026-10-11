import Foundation
import NotchGateKit

/// One message in a session's conversation, as the notch shows it.
struct ConversationMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user, claude
    }

    let id: String
    let role: Role
    var text: String
}

/// Reads a session's conversation out of its Claude Code transcript: what the
/// person typed and what Claude wrote back, without tool calls, tool output or
/// thinking. Runs off the main thread.
enum SessionTranscript {
    /// Bytes read from the end of a transcript; older messages are left out.
    static let tailBytes = 4 * 1024 * 1024
    /// Messages kept, newest last.
    static let maxMessages = 200

    /// The session's transcript: the path its hooks reported, or else found
    /// by its id under `~/.claude/projects`.
    static func url(
        sessionID: String,
        reportedPath: String?,
        root: URL = SessionHistory.projectsDirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        if let reportedPath, !reportedPath.isEmpty, fileManager.fileExists(atPath: reportedPath) {
            return URL(fileURLWithPath: reportedPath)
        }
        guard !sessionID.isEmpty,
              let projects = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return nil }
        let name = sessionID + ".jsonl"
        return projects.lazy
            .map { $0.appendingPathComponent(name) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// The conversation in a transcript, or `nil` if it can't be read.
    static func messages(in url: URL) -> [ConversationMessage]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        // A line still being written fails to decode and is skipped.
        return parse(SessionHistory.lines(in: data, startsMidLine: start > 0, endsMidLine: false))
    }

    /// Prompts and Claude's replies, in order. Claude's text between tool
    /// calls reads as one reply, so consecutive pieces are joined.
    static func parse<S: Sequence>(_ lines: S) -> [ConversationMessage] where S.Element == Data {
        var messages: [ConversationMessage] = []
        let decoder = JSONDecoder()
        for (index, line) in lines.enumerated() where line.count <= SessionHistory.maxLineBytes {
            guard let entry = try? decoder.decode(JSONValue.self, from: line),
                  entry["isSidechain"]?.boolValue != true else { continue }
            let id = entry["uuid"]?.stringValue ?? "line-\(index)"
            switch entry["type"]?.stringValue {
            case "user":
                guard let prompt = SessionHistory.promptText(entry),
                      !prompt.hasPrefix("[Request interrupted") else { continue }
                messages.append(ConversationMessage(id: id, role: .user, text: prompt))
            case "assistant":
                guard let text = replyText(entry) else { continue }
                if let last = messages.last, last.role == .claude {
                    messages[messages.count - 1].text += "\n\n" + text
                } else {
                    messages.append(ConversationMessage(id: id, role: .claude, text: text))
                }
            default:
                continue
            }
        }
        return Array(messages.suffix(maxMessages))
    }

    /// The text blocks of one assistant entry, if it has any.
    private static func replyText(_ entry: JSONValue) -> String? {
        let text = (entry["message"]?["content"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
