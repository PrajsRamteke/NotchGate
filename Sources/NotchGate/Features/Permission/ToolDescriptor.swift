import Foundation
import NotchGateKit

/// What a tool permission request should look like: a human title, a short
/// subtitle and the most useful preview for that particular tool.
struct ToolDescriptor: Equatable {
    enum Preview: Equatable {
        case command(String)
        case diff(path: String, removed: String, added: String)
        case content(path: String, text: String)
        case json(JSONValue)
        case none
    }

    let title: String
    let subtitle: String?
    let preview: Preview

    static func describe(_ permission: ToolPermission) -> ToolDescriptor {
        let input = permission.input
        let path = (input["file_path"] ?? input["notebook_path"] ?? input["path"])?.stringValue.map(abbreviate)

        switch permission.toolName {
        case "Bash", "BashOutput":
            return ToolDescriptor(
                title: "Run a command?",
                subtitle: input["description"]?.stringValue,
                preview: .command(input["command"]?.stringValue ?? "")
            )
        case "Edit":
            return ToolDescriptor(
                title: "Edit \(fileName(path))?",
                subtitle: path,
                preview: .diff(
                    path: path ?? "",
                    removed: input["old_string"]?.stringValue ?? "",
                    added: input["new_string"]?.stringValue ?? ""
                )
            )
        case "MultiEdit":
            let edits = input["edits"]?.arrayValue ?? []
            return ToolDescriptor(
                title: "Make \(edits.count) edits to \(fileName(path))?",
                subtitle: path,
                preview: .diff(
                    path: path ?? "",
                    removed: edits.compactMap { $0["old_string"]?.stringValue }.joined(separator: "\n⋯\n"),
                    added: edits.compactMap { $0["new_string"]?.stringValue }.joined(separator: "\n⋯\n")
                )
            )
        case "Write":
            return ToolDescriptor(
                title: "Write \(fileName(path))?",
                subtitle: path,
                preview: .content(path: path ?? "", text: input["content"]?.stringValue ?? "")
            )
        case "NotebookEdit":
            return ToolDescriptor(
                title: "Edit notebook \(fileName(path))?",
                subtitle: path,
                preview: .content(path: path ?? "", text: input["new_source"]?.stringValue ?? "")
            )
        case "Read":
            return ToolDescriptor(title: "Read \(fileName(path))?", subtitle: path, preview: .none)
        case "WebFetch":
            return ToolDescriptor(
                title: "Fetch a web page?",
                subtitle: input["prompt"]?.stringValue,
                preview: .command(input["url"]?.stringValue ?? "")
            )
        case "WebSearch":
            return ToolDescriptor(
                title: "Search the web?",
                subtitle: nil,
                preview: .command(input["query"]?.stringValue ?? "")
            )
        case "Agent", "Task":
            return ToolDescriptor(
                title: "Start a subagent?",
                subtitle: input["description"]?.stringValue,
                preview: .content(path: "", text: input["prompt"]?.stringValue ?? "")
            )
        case let name where name.hasPrefix("mcp__"):
            // mcp__<server>__<tool>; server names may themselves contain "_".
            let parts = name.components(separatedBy: "__")
            let server = parts.count > 1 ? parts[1] : "MCP"
            let tool = parts.dropFirst(2).joined(separator: "__")
            return ToolDescriptor(
                title: "Use \(tool.isEmpty ? name : tool)?",
                subtitle: "from the \(server) MCP server",
                preview: input.objectValue?.isEmpty == false ? .json(input) : .none
            )
        default:
            return ToolDescriptor(
                title: "Use \(permission.toolName)?",
                subtitle: path,
                preview: input.objectValue?.isEmpty == false ? .json(input) : .none
            )
        }
    }

    /// Human description of the "Always allow" rule Claude Code suggested.
    static func ruleSummary(for suggestion: JSONValue) -> String {
        let rules = suggestion["rules"]?.arrayValue ?? []
        let descriptions = rules.compactMap { rule -> String? in
            guard let tool = rule["toolName"]?.stringValue else { return nil }
            guard let content = rule["ruleContent"]?.stringValue else { return tool }
            return "\(tool)(\(content))"
        }
        let destination: String = switch suggestion["destination"]?.stringValue {
        case "session": "this session"
        case "localSettings": "this project (local)"
        case "projectSettings": "this project"
        case "userSettings": "all projects"
        default: "future requests"
        }
        guard !descriptions.isEmpty else { return "Don't ask again for \(destination)" }
        return "Allow \(descriptions.joined(separator: ", ")) for \(destination)"
    }

    private static func fileName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
