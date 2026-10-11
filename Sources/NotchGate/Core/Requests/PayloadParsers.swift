import Foundation
import NotchGateKit

/// Pure functions that turn raw hook payloads into typed prompts.
enum PayloadParsers {
    static func question(from input: JSONValue) -> QuestionPrompt? {
        let questions = (input["questions"]?.arrayValue ?? []).compactMap { item -> Question? in
            guard let text = item["question"]?.stringValue, !text.isEmpty else { return nil }
            let options = (item["options"]?.arrayValue ?? []).compactMap { option -> Question.Option? in
                guard let label = option["label"]?.stringValue else { return nil }
                return Question.Option(label: label, detail: option["description"]?.stringValue)
            }
            return Question(
                header: item["header"]?.stringValue,
                text: text,
                options: options,
                multiSelect: item["multiSelect"]?.boolValue ?? false
            )
        }
        return questions.isEmpty ? nil : QuestionPrompt(questions: questions, originalInput: input)
    }

    static func plan(from input: JSONValue) -> PlanPrompt {
        PlanPrompt(
            markdown: input["plan"]?.stringValue ?? "",
            filePath: input["planFilePath"]?.stringValue,
            originalInput: input
        )
    }

    static func elicitation(from payload: JSONValue) -> ElicitationPrompt {
        let schema = payload["requested_schema"]
        let required = Set((schema?["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        let properties = schema?["properties"]?.objectValue ?? [:]

        let fields = properties.keys.sorted().compactMap { key -> ElicitationField? in
            guard let property = properties[key] else { return nil }
            return ElicitationField(
                id: key,
                title: property["title"]?.stringValue ?? key,
                detail: property["description"]?.stringValue,
                kind: fieldKind(for: property),
                isRequired: required.contains(key),
                defaultValue: property["default"]
            )
        }

        return ElicitationPrompt(
            server: payload["mcp_server_name"]?.stringValue ?? "MCP server",
            message: payload["message"]?.stringValue ?? "",
            url: payload["url"]?.stringValue.flatMap(URL.init(string:)),
            fields: fields
        )
    }

    private static func fieldKind(for property: JSONValue) -> ElicitationField.Kind {
        if let choices = property["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
            return .choice(choices)
        }
        switch property["type"]?.stringValue {
        case "boolean": return .boolean
        case "integer": return .integer
        case "number": return .number
        default: return .text
        }
    }
}
