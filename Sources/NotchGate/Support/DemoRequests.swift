import Foundation
import NotchGateKit

/// Sample requests for previewing the island from the menu bar.
enum DemoRequests {
    enum Sample: String, CaseIterable, Identifiable {
        case permission = "Permission"
        case edit = "File edit"
        case question = "Question"
        case plan = "Plan"
        case completion = "Reply"

        var id: String { rawValue }
    }

    private static let session = SessionInfo(id: "demo", cwd: "/Users/demo/NotchGate", claudePID: 0)

    static func make(_ sample: Sample, sessionID: String? = nil) -> ClaudeRequest {
        ClaudeRequest(
            id: UUID(),
            event: .permissionRequest,
            session: sessionID.map { SessionInfo(id: $0, cwd: session.cwd, claudePID: 0) } ?? session,
            kind: kind(for: sample)
        )
    }

    private static func kind(for sample: Sample) -> RequestKind {
        switch sample {
        case .permission:
            return .permission(ToolPermission(
                toolName: "Bash",
                input: .object([
                    "command": .string("npm run build && npm test -- --coverage"),
                    "description": .string("Build the project and run the test suite"),
                ]),
                suggestions: [.object([
                    "type": .string("addRules"),
                    "rules": .array([.object(["toolName": .string("Bash"), "ruleContent": .string("npm test:*")])]),
                    "behavior": .string("allow"),
                    "destination": .string("localSettings"),
                ])]
            ))
        case .edit:
            return .permission(ToolPermission(
                toolName: "Edit",
                input: .object([
                    "file_path": .string("/Users/demo/NotchGate/Sources/App.swift"),
                    "old_string": .string("let timeout = 30\nretry(count: 1)"),
                    "new_string": .string("let timeout = 120\nretry(count: 3, backoff: .exponential)"),
                ]),
                suggestions: []
            ))
        case .question:
            return .question(QuestionPrompt(
                questions: [Question(
                    header: "Storage",
                    text: "Which storage engine should the cache use?",
                    options: [
                        .init(label: "SQLite", detail: "Durable, queryable, a little heavier"),
                        .init(label: "In-memory LRU", detail: "Fastest, lost on restart"),
                    ],
                    multiSelect: false
                )],
                originalInput: .object([:])
            ))
        case .plan:
            return .plan(PlanPrompt(
                markdown: """
                ## Add offline sync
                1. Introduce a `SyncQueue` actor that persists pending writes
                2. Retry with exponential backoff when the network returns
                - Update **SettingsView** with a sync status row
                - Add unit tests for conflict resolution
                """,
                filePath: nil,
                originalInput: .object([:])
            ))
        case .completion:
            return .completion(CompletionPrompt(
                summary: "Refactored the bridge layer and added **12 tests**. All checks pass."
            ))
        }
    }
}

/// Swallows decisions for demo requests.
final class DemoResponder: DecisionResponder {
    func send(_ decision: BridgeDecision) {
        Log.app.debug("Demo decision: \(String(describing: decision), privacy: .public)")
    }
}
