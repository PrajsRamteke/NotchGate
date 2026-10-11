import NotchGateKit
import SwiftUI

/// An MCP server asking for structured input (form mode) or for the user
/// to visit a URL (url mode).
struct ElicitationCardView: View {
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void

    @State private var form: ElicitationFormModel

    init(prompt: ElicitationPrompt, onFocus: @escaping () -> Void, onDecision: @escaping (BridgeDecision) -> Void) {
        self.onFocus = onFocus
        self.onDecision = onDecision
        _form = State(initialValue: ElicitationFormModel(prompt: prompt))
    }

    private var prompt: ElicitationPrompt { form.prompt }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(
                title: prompt.message.isEmpty ? "\(prompt.server) needs input" : prompt.message,
                subtitle: form.isURLMode ? prompt.url?.host() : "Requested by \(prompt.server)"
            )

            if !prompt.fields.isEmpty {
                CappedScroll(maxHeight: 280) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(prompt.fields) { field in
                            ElicitationFieldView(field: field, form: form, onFocus: onFocus)
                        }
                    }
                }
            }

            ActionRow {
                LinkButton(title: "Cancel") { onDecision(.elicitation(action: .cancel)) }
            } actions: {
                Button("Decline") { onDecision(.elicitation(action: .decline)) }
                    .buttonStyle(.island(.destructive))
                    .keyboardShortcut(.cancelAction)

                if form.isURLMode, let url = prompt.url {
                    Button("Open link") {
                        NSWorkspace.shared.open(url)
                        onDecision(.elicitation(action: .accept))
                    }
                    .buttonStyle(.island(.primary, shortcut: "⏎"))
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Submit") { onDecision(.elicitation(action: .accept, content: form.content)) }
                        .buttonStyle(.island(.primary, shortcut: "⏎"))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!form.isValid)
                }
            }
        }
    }
}
