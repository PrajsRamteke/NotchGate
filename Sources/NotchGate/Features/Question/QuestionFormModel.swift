import Foundation
import Observation

/// Form state for an `AskUserQuestion` request: one or more questions, each
/// single- or multi-select, each with a free-text "Other" escape hatch.
@MainActor
@Observable
final class QuestionFormModel {
    let prompt: QuestionPrompt

    private(set) var index = 0
    private var selections: [String: Set<String>] = [:]
    private var otherSelected: Set<String> = []
    var otherText: [String: String] = [:]

    /// Joiner Claude Code expects for multi-select answers.
    static let multiSelectSeparator = ", "

    init(prompt: QuestionPrompt) {
        self.prompt = prompt
    }

    var question: Question { prompt.questions[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == prompt.questions.count - 1 }
    var count: Int { prompt.questions.count }

    // MARK: Selection

    func isSelected(_ option: Question.Option) -> Bool {
        selections[question.id]?.contains(option.label) == true
    }

    var isOtherSelected: Bool { otherSelected.contains(question.id) }

    func toggle(_ option: Question.Option) {
        let id = question.id
        if question.multiSelect {
            var set = selections[id] ?? []
            if set.contains(option.label) { set.remove(option.label) } else { set.insert(option.label) }
            selections[id] = set
        } else {
            selections[id] = [option.label]
            otherSelected.remove(id)
        }
    }

    func toggleOther() {
        let id = question.id
        if otherSelected.contains(id) {
            otherSelected.remove(id)
        } else {
            otherSelected.insert(id)
            if !question.multiSelect { selections[id] = [] }
        }
    }

    // MARK: Navigation

    func canAdvance(_ question: Question? = nil) -> Bool {
        answer(for: question ?? self.question) != nil
    }

    func next() { if !isLast { index += 1 } }
    func back() { if !isFirst { index -= 1 } }

    // MARK: Output

    /// Answers keyed by question text, or `nil` while any question is unanswered.
    var answers: [String: String]? {
        var result: [String: String] = [:]
        for question in prompt.questions {
            guard let answer = answer(for: question) else { return nil }
            result[question.text] = answer
        }
        return result
    }

    private func answer(for question: Question) -> String? {
        let chosen = selections[question.id] ?? []
        // Preserve the order options were presented in.
        var parts = question.options.map(\.label).filter(chosen.contains)
        if otherSelected.contains(question.id) {
            let custom = (otherText[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { parts.append(custom) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: Self.multiSelectSeparator)
    }
}
