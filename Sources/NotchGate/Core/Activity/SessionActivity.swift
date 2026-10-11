import Foundation

/// Live state of one Claude Code session, built from hook events.
struct SessionActivity: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case thinking
        case running(ToolStep)
        case waiting(reason: String)
        case compacting
        case finished
    }

    let id: String
    var cwd: String
    var claudePID: Int32
    var phase: Phase = .idle
    /// The prompt that started the current turn.
    var prompt: String?
    /// Claude's final message from the last finished turn.
    var lastMessage: String?
    var toolCount = 0
    var tasks: [TaskItem] = []
    /// Files added, changed and deleted this session.
    var fileChanges = FileChanges()
    /// Tools called this session, by kind (the Tools widget).
    var toolUsage = ToolUsage()
    var turnStartedAt: Date?
    var turnEndedAt: Date?
    var updatedAt: Date

    var projectName: String {
        SessionInfo(id: id, cwd: cwd, claudePID: claudePID).projectName
    }

    var isWorking: Bool {
        switch phase {
        case .thinking, .running, .compacting: return true
        case .idle, .waiting, .finished: return false
        }
    }

    var progress: TaskProgress? {
        tasks.isEmpty ? nil : TaskProgress(tasks: tasks)
    }
}

/// One tool call shown as the session's current step.
struct ToolStep: Equatable, Sendable {
    let toolName: String
    let summary: String
    let symbol: String
    let startedAt: Date
}

/// An item from Claude's to-do list (`TodoWrite` or `TaskCreate`/`TaskUpdate`).
struct TaskItem: Equatable, Sendable {
    enum Status: String, Sendable {
        case pending, inProgress = "in_progress", completed
    }

    let id: String
    var title: String
    var activeTitle: String?
    var status: Status
}

struct TaskProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    /// What Claude is doing right now, phrased the way its to-do list says it.
    let current: String?

    init(tasks: [TaskItem]) {
        completed = tasks.filter { $0.status == .completed }.count
        total = tasks.count
        current = tasks.first { $0.status == .inProgress }.map { $0.activeTitle ?? $0.title }
    }

    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}
