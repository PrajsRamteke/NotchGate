import SwiftUI

/// One Claude session in the hover panel: what it's doing, how far along and
/// for how long, plus a "Reply" dropdown to send that project a prompt.
struct SessionActivityRow<Composer: View>: View {
    let session: SessionActivity
    let isComposerOpen: Bool
    let hasQueuedPrompt: Bool
    let onToggleComposer: () -> Void
    let onOpen: () -> Void
    @ViewBuilder var composer: Composer

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PhaseIndicator(phase: session.phase)
                Text(session.projectName)
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ElapsedLabel(session: session)
                ReplyChip(isOpen: isComposerOpen, isQueued: hasQueuedPrompt, action: onToggleComposer)
                IconButton(systemName: "arrow.up.forward.app", help: "Open this session's terminal", action: onOpen)
            }

            HStack(spacing: 6) {
                if case .running(let step) = session.phase {
                    Image(systemName: step.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.clay)
                }
                Text(statusLine)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if session.toolCount > 0 {
                    Text("\(session.toolCount) steps")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .monospacedDigit()
                }
            }

            if let progress = session.progress {
                TaskProgressBar(progress: progress)
            }

            if let prompt = session.prompt, !prompt.isEmpty {
                Text("“\(prompt.replacingOccurrences(of: "\n", with: " "))”")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            if isComposerOpen {
                composer
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered || isComposerOpen ? Theme.Palette.surfaceRaised : Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isComposerOpen ? Theme.Palette.clay.opacity(0.35) : Theme.Palette.hairline, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(Theme.Motion.content, value: isComposerOpen)
    }

    private var statusLine: String {
        switch session.phase {
        case .idle: return "Ready for your next message"
        case .thinking: return "Thinking…"
        case .running(let step): return step.summary
        case .waiting(let reason): return reason
        case .compacting: return "Compacting the conversation…"
        case .finished:
            return session.lastMessage.map { $0.replacingOccurrences(of: "\n", with: " ") } ?? "Finished"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .waiting: return Theme.Palette.clayGlow
        case .finished, .idle: return Theme.Palette.textSecondary
        default: return Theme.Palette.textPrimary
        }
    }
}

/// Spinning spark while working, solid dots for other states.
private struct PhaseIndicator: View {
    let phase: SessionActivity.Phase

    var body: some View {
        switch phase {
        case .thinking, .running, .compacting:
            ClaudeSpark(size: 13, isActive: true)
        case .waiting:
            dot(Theme.Palette.clay).overlay(Circle().stroke(Theme.Palette.clay.opacity(0.4), lineWidth: 3))
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.success)
        case .idle:
            dot(Theme.Palette.textTertiary)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7).frame(width: 13, height: 13)
    }
}

/// Live "2m 14s" for a running turn, or how long the finished turn took.
private struct ElapsedLabel: View {
    let session: SessionActivity

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let start = session.turnStartedAt {
                let end = session.turnEndedAt ?? (session.isWorking ? context.date : session.updatedAt)
                Text(Self.format(end.timeIntervalSince(start)))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return String(format: "%dm %02ds", seconds / 60, seconds % 60) }
        return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
    }
}

/// "Reply ▾" toggle that opens the row's prompt field.
private struct ReplyChip: View {
    let isOpen: Bool
    let isQueued: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isQueued ? "clock" : "text.bubble")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isOpen || isHovered ? Theme.Palette.ivory : Theme.Palette.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(isOpen ? Theme.Palette.clay : (isHovered ? Theme.Palette.surfaceRaised : Theme.Palette.surface)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isQueued ? "Message queued for this project" : "Send this project a prompt")
        .accessibilityLabel("Reply to this session")
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isOpen)
    }
}
