import Foundation
import Testing
@testable import NotchGate

@Suite("Session transcript")
struct SessionTranscriptTests {
    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func prompt(_ text: String, uuid: String) -> Data {
        line(["type": "user", "uuid": uuid, "message": ["role": "user", "content": text]])
    }

    private func reply(_ blocks: [[String: Any]], uuid: String) -> Data {
        line(["type": "assistant", "uuid": uuid, "message": ["role": "assistant", "content": blocks]])
    }

    @Test func keepsPromptsAndRepliesButNotToolTraffic() {
        let messages = SessionTranscript.parse([
            prompt("what is the current branch", uuid: "u1"),
            reply([["type": "thinking", "thinking": "hmm"]], uuid: "a1"),
            reply([["type": "tool_use", "id": "t1", "name": "Bash", "input": [:]]], uuid: "a2"),
            line(["type": "user", "uuid": "r1", "message": ["role": "user", "content": [
                ["type": "tool_result", "tool_use_id": "t1", "content": "main"],
            ]]]),
            reply([["type": "text", "text": "You're on `main`."]], uuid: "a3"),
        ])

        #expect(messages == [
            ConversationMessage(id: "u1", role: .user, text: "what is the current branch"),
            ConversationMessage(id: "a3", role: .claude, text: "You're on `main`."),
        ])
    }

    @Test func joinsClaudesTextAcrossToolCallsIntoOneReply() {
        let messages = SessionTranscript.parse([
            prompt("fix it", uuid: "u1"),
            reply([["type": "text", "text": "Looking at the code."]], uuid: "a1"),
            reply([["type": "tool_use", "id": "t1", "name": "Read", "input": [:]]], uuid: "a2"),
            reply([["type": "text", "text": "Fixed."]], uuid: "a3"),
        ])

        #expect(messages.count == 2)
        #expect(messages[1] == ConversationMessage(id: "a1", role: .claude, text: "Looking at the code.\n\nFixed."))
    }

    @Test func skipsGeneratedUserEntriesAndSubagents() {
        let messages = SessionTranscript.parse([
            prompt("<command-name>/model</command-name>", uuid: "c1"),
            prompt("[Request interrupted by user]", uuid: "i1"),
            line(["type": "user", "uuid": "m1", "isMeta": true, "message": ["role": "user", "content": "meta"]]),
            line(["type": "assistant", "uuid": "s1", "isSidechain": true, "message": [
                "role": "assistant", "content": [["type": "text", "text": "subagent"]],
            ]]),
            prompt("real question", uuid: "u1"),
        ])

        #expect(messages.map(\.id) == ["u1"])
    }

    @Test func findsTheTranscriptByIdWhenNoPathWasReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("-tmp-shop")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("abc.jsonl")
        try (String(decoding: prompt("hello", uuid: "u1"), as: UTF8.self) + "\n").write(to: file, atomically: true, encoding: .utf8)

        let found = SessionTranscript.url(sessionID: "abc", reportedPath: nil, root: root)
        #expect(found?.standardizedFileURL == file.standardizedFileURL)
        #expect(found.flatMap(SessionTranscript.messages(in:))?.map(\.text) == ["hello"])
        #expect(SessionTranscript.url(sessionID: "missing", reportedPath: nil, root: root) == nil)
    }
}
