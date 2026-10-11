import Foundation
import NotchGateKit
import Observation

/// Form state for an MCP elicitation built from its JSON schema.
@MainActor
@Observable
final class ElicitationFormModel {
    let prompt: ElicitationPrompt
    var text: [String: String] = [:]
    var flags: [String: Bool] = [:]

    init(prompt: ElicitationPrompt) {
        self.prompt = prompt
        for field in prompt.fields {
            switch (field.kind, field.defaultValue) {
            case (.boolean, let value):
                flags[field.id] = value?.boolValue ?? false
            case (_, .string(let value)?):
                text[field.id] = value
            case (_, .number(let value)?):
                text[field.id] = field.kind == .integer ? String(Int(value)) : String(value)
            default:
                text[field.id] = ""
            }
        }
    }

    var isURLMode: Bool { prompt.url != nil && prompt.fields.isEmpty }

    var isValid: Bool {
        prompt.fields.allSatisfy { field in
            guard field.kind != .boolean else { return true }
            let raw = (text[field.id] ?? "").trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { return !field.isRequired }
            return value(for: field, raw: raw) != nil
        }
    }

    /// Typed values matching the requested schema; empty optionals are omitted.
    var content: JSONValue {
        var result: [String: JSONValue] = [:]
        for field in prompt.fields {
            if field.kind == .boolean {
                result[field.id] = .bool(flags[field.id] ?? false)
                continue
            }
            let raw = (text[field.id] ?? "").trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty, let value = value(for: field, raw: raw) { result[field.id] = value }
        }
        return .object(result)
    }

    private func value(for field: ElicitationField, raw: String) -> JSONValue? {
        switch field.kind {
        case .text: return .string(raw)
        case .choice(let options): return options.contains(raw) ? .string(raw) : nil
        case .integer: return Int(raw).map { .number(Double($0)) }
        case .number: return Double(raw).map(JSONValue.number)
        case .boolean: return nil
        }
    }
}
