import SwiftUI

/// Kind chip, queue position and window chrome shown atop every request card.
struct RequestHeaderView: View {
    let request: ClaudeRequest
    let pendingCount: Int
    let onOpenTerminal: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            KindChip(kind: request.kind)
            if pendingCount > 1 {
                Text("1 of \(pendingCount)")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(request.receivedAt, style: .relative)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            IconButton(systemName: "arrow.up.forward.app", help: "Open in terminal", action: onOpenTerminal)
            IconButton(systemName: "chevron.up", help: "Minimize to notch  ⌃⌥Space", action: onCollapse)
        }
    }
}

private struct KindChip: View {
    let kind: RequestKind

    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(Theme.Typeface.micro)
            .foregroundStyle(Theme.Palette.clay)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.Palette.clay.opacity(0.12)))
    }
}

extension RequestKind {
    var label: String {
        switch self {
        case .permission: return "Permission"
        case .question: return "Question"
        case .plan: return "Plan review"
        case .elicitation(let prompt): return prompt.server
        case .completion: return "Finished"
        }
    }

    var symbol: String {
        switch self {
        case .permission: return "lock.shield"
        case .question: return "questionmark.bubble"
        case .plan: return "list.bullet.clipboard"
        case .elicitation: return "puzzlepiece.extension"
        case .completion: return "checkmark.seal"
        }
    }
}
