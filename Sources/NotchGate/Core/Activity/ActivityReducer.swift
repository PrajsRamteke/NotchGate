import Foundation
import NotchGateKit

/// Pure state machine: (sessions, hook event) → sessions.
/// Kept free of UI and timers so every transition is unit-testable.
enum ActivityReducer {
    /// - Parameter removedPaths: files a finished `Bash` call deleted (found
    ///   by `ActivityTracker`, which can look at the disk).
    static func reduce(
        _ sessions: [String: SessionActivity],
        _ message: BridgeRequest,
        removedPaths: [String] = [],
        now: Date = .now
    ) -> [String: SessionActivity] {
        let payload = message.payload
        guard let id = payload["session_id"]?.stringValue else { return sessions }
        var sessions = sessions

        if message.event == .sessionEnd {
            sessions[id] = nil
            return sessions
        }

        var session = sessions[id] ?? SessionActivity(
            id: id, cwd: "", claudePID: message.origin.claudePID, updatedAt: now
        )
        if let cwd = payload["cwd"]?.stringValue, !cwd.isEmpty { session.cwd = cwd }
        session.claudePID = message.origin.claudePID
        session.updatedAt = now
        apply(message.event, payload, to: &session, now: now)
        if message.event == .postToolUse {
            recordFileChanges(payload, removedPaths: removedPaths, in: &session.fileChanges)
        }
        sessions[id] = session
        return sessions
    }

    private static func apply(_ event: HookEvent, _ payload: JSONValue, to session: inout SessionActivity, now: Date) {
        let tool = payload["tool_name"]?.stringValue ?? ""
        let input = payload["tool_input"] ?? .object([:])

        switch event {
        case .sessionStart:
            if payload["source"]?.stringValue != "compact" {
                session.tasks = []
                session.fileChanges = FileChanges()
                session.prompt = nil
                session.lastMessage = nil
            }
            session.phase = .idle

        case .userPromptSubmit:
            session.phase = .thinking
            session.prompt = payload["prompt"]?.stringValue
            session.turnStartedAt = now
            session.turnEndedAt = nil
            session.toolCount = 0

        case .preToolUse:
            if session.turnStartedAt == nil { session.turnStartedAt = now }
            switch tool {
            case "AskUserQuestion": session.phase = .waiting(reason: "Asking you a question")
            case "ExitPlanMode": session.phase = .waiting(reason: "Waiting for plan approval")
            default:
                session.toolCount += 1
                session.phase = .running(ToolSummary.step(toolName: tool, input: input, at: now))
            }
            if tool == "TodoWrite" { session.tasks = TaskParser.todoList(from: input) }

        case .postToolUse:
            session.tasks = TaskParser.apply(tool: tool, input: input, response: payload["tool_response"], to: session.tasks)
            session.phase = .thinking

        case .permissionRequest:
            let (summary, _) = ToolSummary.describe(toolName: tool, input: input)
            session.phase = .waiting(reason: "Needs permission · \(summary)")

        case .elicitation:
            let server = payload["mcp_server_name"]?.stringValue ?? "An MCP server"
            session.phase = .waiting(reason: "\(server) needs input")

        case .preCompact:
            session.phase = .compacting

        case .stop:
            session.phase = .finished
            session.lastMessage = payload["last_assistant_message"]?.stringValue
            session.turnEndedAt = now

        default:
            break
        }
    }

    /// File tools report what they did in `file_change` (see `HookPolicy`); an
    /// older hook binary doesn't, so its edits count as changes with no lines.
    private static func recordFileChanges(_ payload: JSONValue, removedPaths: [String], in changes: inout FileChanges) {
        for path in removedPaths { changes.record(.deleted, path: path) }

        let tool = payload["tool_name"]?.stringValue ?? ""
        guard HookPolicy.fileTools.contains(tool),
              let path = payload["tool_input"]?["file_path"]?.stringValue
                ?? payload["tool_input"]?["notebook_path"]?.stringValue else { return }
        let change = payload["file_change"]
        changes.record(
            change?["created"]?.boolValue == true ? .added : .modified,
            path: path,
            linesAdded: Int(change?["lines_added"]?.doubleValue ?? 0),
            linesRemoved: Int(change?["lines_removed"]?.doubleValue ?? 0)
        )
    }
}

/// Reads Claude's to-do lists out of task-tool payloads.
enum TaskParser {
    static func todoList(from input: JSONValue) -> [TaskItem] {
        (input["todos"]?.arrayValue ?? []).enumerated().compactMap { index, todo in
            guard let title = todo["content"]?.stringValue else { return nil }
            return TaskItem(
                id: todo["id"]?.stringValue ?? String(index + 1),
                title: title,
                activeTitle: todo["activeForm"]?.stringValue,
                status: TaskItem.Status(rawValue: todo["status"]?.stringValue ?? "") ?? .pending
            )
        }
    }

    static func apply(tool: String, input: JSONValue, response: JSONValue?, to tasks: [TaskItem]) -> [TaskItem] {
        var tasks = tasks
        switch tool {
        case "TaskCreate":
            guard let title = input["subject"]?.stringValue else { return tasks }
            let id = response.flatMap(findID) ?? String(tasks.count + 1)
            tasks.append(TaskItem(id: id, title: title, activeTitle: input["activeForm"]?.stringValue, status: .pending))
        case "TaskUpdate":
            guard let id = input["taskId"].flatMap(scalarString),
                  let index = tasks.firstIndex(where: { $0.id == id }) else { return tasks }
            let status = input["status"]?.stringValue
            if status == "deleted" { tasks.remove(at: index); return tasks }
            if let status, let parsed = TaskItem.Status(rawValue: status) { tasks[index].status = parsed }
            if let subject = input["subject"]?.stringValue { tasks[index].title = subject }
            if let active = input["activeForm"]?.stringValue { tasks[index].activeTitle = active }
        default:
            break
        }
        return tasks
    }

    /// Finds a task id anywhere in a tool response (`id` / `taskId`).
    private static func findID(in value: JSONValue) -> String? {
        if let object = value.objectValue {
            for key in ["taskId", "id"] { if let id = object[key].flatMap(scalarString) { return id } }
            return object.values.lazy.compactMap(findID).first
        }
        return value.arrayValue?.lazy.compactMap(findID).first
    }

    private static func scalarString(_ value: JSONValue) -> String? {
        if let string = value.stringValue { return string }
        return value.doubleValue.map { String(Int($0)) }
    }
}
