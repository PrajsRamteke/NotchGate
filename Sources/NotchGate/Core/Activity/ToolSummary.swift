import Foundation
import NotchGateKit

/// Present-tense, one-line descriptions of tool calls for the activity panel
/// ("Running npm test", "Editing App.swift").
enum ToolSummary {
    static func step(toolName: String, input: JSONValue, at date: Date) -> ToolStep {
        let (summary, symbol) = describe(toolName: toolName, input: input)
        return ToolStep(toolName: toolName, summary: summary, symbol: symbol, startedAt: date)
    }

    static func describe(toolName: String, input: JSONValue) -> (String, String) {
        let file = (input["file_path"] ?? input["notebook_path"] ?? input["path"])?.stringValue
            .map { URL(fileURLWithPath: $0).lastPathComponent }

        switch toolName {
        case "Bash":
            let label = input["description"]?.stringValue ?? input["command"]?.stringValue ?? "a command"
            return ("Running \(firstLine(label))", "terminal")
        case "Read":
            return ("Reading \(file ?? "a file")", "doc.text")
        case "Edit", "MultiEdit", "NotebookEdit":
            return ("Editing \(file ?? "a file")", "pencil")
        case "Write":
            return ("Writing \(file ?? "a file")", "square.and.pencil")
        case "Grep":
            return ("Searching for “\(input["pattern"]?.stringValue ?? "…")”", "magnifyingglass")
        case "Glob":
            return ("Finding \(input["pattern"]?.stringValue ?? "files")", "folder")
        case "WebFetch":
            let host = input["url"]?.stringValue.flatMap { URL(string: $0)?.host() } ?? "the web"
            return ("Reading \(host)", "globe")
        case "WebSearch":
            return ("Searching the web for “\(input["query"]?.stringValue ?? "…")”", "globe")
        case "Agent", "Task":
            return ("Subagent: \(input["description"]?.stringValue ?? "working")", "person.2")
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet":
            return ("Updating the plan", "checklist")
        case "AskUserQuestion":
            return ("Asking you a question", "questionmark.bubble")
        case "ExitPlanMode":
            return ("Presenting a plan", "list.bullet.clipboard")
        case let name where name.hasPrefix("mcp__"):
            let parts = name.components(separatedBy: "__")
            let tool = parts.count > 2 ? parts[2] : name
            let server = parts.count > 1 ? parts[1] : "MCP"
            return ("\(tool.replacingOccurrences(of: "_", with: " ")) · \(server)", "puzzlepiece.extension")
        default:
            return ("Using \(toolName)", "wrench.and.screwdriver")
        }
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }
}
