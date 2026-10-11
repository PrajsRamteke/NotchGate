import NotchGateKit
import SwiftUI

/// Answers Claude's `AskUserQuestion` without leaving your current app.
struct QuestionCardView: View {
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void

    @State private var form: QuestionFormModel

    init(prompt: QuestionPrompt, onFocus: @escaping () -> Void, onDecision: @escaping (BridgeDecision) -> Void) {
        self.onFocus = onFocus
        self.onDecision = onDecision
        _form = State(initialValue: QuestionFormModel(prompt: prompt))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            CardTitle(title: form.question.text, subtitle: form.question.multiSelect ? "Select all that apply" : nil)

            CappedScroll(maxHeight: 260) {
                VStack(spacing: 6) {
                    ForEach(form.question.options, id: \.self) { option in
                        QuestionOptionRow(
                            label: option.label,
                            detail: option.detail,
                            isSelected: form.isSelected(option),
                            isMultiSelect: form.question.multiSelect
                        ) { form.toggle(option) }
                    }
                    QuestionOptionRow(
                        label: "Other",
                        detail: "Write your own answer",
                        isSelected: form.isOtherSelected,
                        isMultiSelect: form.question.multiSelect,
                        action: form.toggleOther
                    )
                }
            }
            .id(form.index)
            .transition(.opacity)

            if form.isOtherSelected {
                ReplyField(
                    placeholder: "Your answer…",
                    text: otherBinding,
                    autofocus: true,
                    onSubmit: advance,
                    onFocus: onFocus
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ActionRow {
                LinkButton(title: "Answer in terminal") { onDecision(.passthrough) }
            } actions: {
                if !form.isFirst {
                    Button("Back") { withAnimation(Theme.Motion.content) { form.back() } }
                        .buttonStyle(.island(.secondary))
                }
                Button(form.isLast ? "Submit" : "Next", action: advance)
                    .buttonStyle(.island(.primary, shortcut: "⏎"))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canAdvance())
            }
        }
        .animation(Theme.Motion.content, value: form.isOtherSelected)
    }

    @ViewBuilder
    private var progress: some View {
        if form.count > 1 || form.question.header != nil {
            HStack(spacing: 8) {
                if let header = form.question.header {
                    Text(header.uppercased())
                        .font(Theme.Typeface.micro)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                if form.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<form.count, id: \.self) { step in
                            Capsule()
                                .fill(step == form.index ? Theme.Palette.clay : Theme.Palette.hairline)
                                .frame(width: step == form.index ? 14 : 6, height: 6)
                        }
                    }
                    .animation(Theme.Motion.content, value: form.index)
                }
            }
        }
    }

    private var otherBinding: Binding<String> {
        let id = form.question.id
        return Binding(get: { form.otherText[id] ?? "" }, set: { form.otherText[id] = $0 })
    }

    private func advance() {
        guard form.canAdvance() else { return }
        if form.isLast {
            guard let answers = form.answers else { return }
            onDecision(.allow(updatedInput: form.prompt.input(withAnswers: answers)))
        } else {
            withAnimation(Theme.Motion.content) { form.next() }
        }
    }
}
