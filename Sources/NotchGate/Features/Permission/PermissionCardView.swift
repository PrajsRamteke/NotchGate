import NotchGateKit
import SwiftUI

/// Allow / Deny / Always allow for a tool call.
struct PermissionCardView: View {
    let permission: ToolPermission
    let onFocus: () -> Void
    let onDecision: (BridgeDecision) -> Void

    @State private var isWritingNote = false
    @State private var note = ""

    private var descriptor: ToolDescriptor { .describe(permission) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: descriptor.title, subtitle: descriptor.subtitle)
            ToolPreviewView(preview: descriptor.preview)

            if isWritingNote {
                ReplyField(
                    placeholder: "Tell Claude what to do instead…",
                    text: $note,
                    autofocus: true,
                    onSubmit: deny,
                    onFocus: onFocus
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ActionRow {
                if !isWritingNote {
                    LinkButton(title: "Deny with a note…") {
                        withAnimation(Theme.Motion.content) { isWritingNote = true }
                    }
                }
            } actions: {
                Button("Deny", action: deny)
                    .buttonStyle(.island(.destructive))
                    .keyboardShortcut(.cancelAction)

                if let suggestion = permission.suggestions.first {
                    Button("Always allow") {
                        onDecision(.allow(updatedPermissions: [suggestion]))
                    }
                    .buttonStyle(.island(.secondary))
                    .help(ToolDescriptor.ruleSummary(for: suggestion))
                }

                Button("Allow") { onDecision(.allow()) }
                    .buttonStyle(.island(.primary, shortcut: "⏎"))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func deny() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onDecision(.deny(message: trimmed.isEmpty ? "The user denied this action." : trimmed))
    }
}
