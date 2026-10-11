import Foundation
import NotchGateKit

/// The shape of an interactive request. Each case maps to a feature card.
enum RequestKind: Equatable, Sendable {
    case permission(ToolPermission)
    case question(QuestionPrompt)
    case plan(PlanPrompt)
    case elicitation(ElicitationPrompt)
    case completion(CompletionPrompt)
}

// MARK: - Permission

struct ToolPermission: Equatable, Sendable {
    let toolName: String
    let input: JSONValue
    /// Claude Code's suggested rule updates; echoing one back = "Always allow".
    let suggestions: [JSONValue]
}

// MARK: - Question (AskUserQuestion)

struct QuestionPrompt: Equatable, Sendable {
    let questions: [Question]
    let originalInput: JSONValue

    /// Builds the tool input carrying the user's answers, keyed by question text.
    func input(withAnswers answers: [String: String]) -> JSONValue {
        originalInput.setting("answers", to: .object(answers.mapValues(JSONValue.string)))
    }
}

struct Question: Identifiable, Equatable, Sendable {
    struct Option: Hashable, Sendable {
        let label: String
        let detail: String?
    }

    var id: String { text }
    let header: String?
    let text: String
    let options: [Option]
    let multiSelect: Bool
}

// MARK: - Plan (ExitPlanMode)

struct PlanPrompt: Equatable, Sendable {
    let markdown: String
    let filePath: String?
    let originalInput: JSONValue
}

// MARK: - MCP elicitation

struct ElicitationPrompt: Equatable, Sendable {
    let server: String
    let message: String
    let url: URL?
    let fields: [ElicitationField]
}

struct ElicitationField: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text, number, integer, boolean
        case choice([String])
    }

    let id: String
    let title: String
    let detail: String?
    let kind: Kind
    let isRequired: Bool
    let defaultValue: JSONValue?
}

// MARK: - Completion (Stop)

struct CompletionPrompt: Equatable, Sendable {
    let summary: String?
}
