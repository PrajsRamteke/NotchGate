import SwiftUI

/// How a session row looks while images are dragged over the notch.
enum SessionDropState: Equatable {
    case none
    /// Images are being dragged: this row can take them.
    case available
    /// The images are over this row; letting go attaches them here.
    case targeted
}

/// One Claude session in the hover panel: what it's doing, how far along and
/// for how long, plus a "Reply" dropdown to send that project a prompt.
struct SessionActivityRow<Composer: View>: View {
    let session: SessionActivity
    let isComposerOpen: Bool
    let hasQueuedPrompt: Bool
    var dropState: SessionDropState = .none
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
                if !session.fileChanges.isEmpty {
                    FileChangeBadge(changes: session.fileChanges)
                }
                ElapsedLabel(session: session)
                ReplyChip(isOpen: isComposerOpen, isQueued: hasQueuedPrompt, action: onToggleComposer)
                IconButton(systemName: "arrow.up.forward.app", help: "Open this session's terminal", action: onOpen)
            }

            if dropState == .targeted {
                Label("Drop to attach to this session's next prompt", systemImage: "photo.badge.plus")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.clayGlow)
                    .lineLimit(1)
            } else {
                statusRow
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
                .fill(background)
        )
        .overlay(border)
        .scaleEffect(dropState == .targeted ? 1.015 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(Theme.Motion.content, value: isComposerOpen)
        .animation(Theme.Motion.press, value: dropState)
    }

    private var statusRow: some View {
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
    }

    private var background: Color {
        switch dropState {
        case .targeted: return Theme.Palette.clay.opacity(0.14)
        case .available, .none:
            return isHovered || isComposerOpen ? Theme.Palette.surfaceRaised : Theme.Palette.surface
        }
    }

    /// Dashed clay outline marks every row as a drop target; solid on the one under the cursor.
    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch dropState {
        case .targeted:
            shape.strokeBorder(Theme.Palette.clay, lineWidth: 1.5)
        case .available:
            shape.strokeBorder(Theme.Palette.clay.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        case .none:
            shape.strokeBorder(isComposerOpen ? Theme.Palette.clay.opacity(0.35) : Theme.Palette.hairline, lineWidth: 0.5)
        }
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

/// "+2 ~3 −1": files this session added (green), changed (yellow) and
/// deleted (red). Hover for the line counts.
private struct FileChangeBadge: View {
    let changes: FileChanges

    var body: some View {
        HStack(spacing: 6) {
            count("+", changes.added, Theme.Palette.success)
            count("~", changes.modified, Theme.Palette.warning)
            count("−", changes.deleted, Theme.Palette.danger)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .fixedSize()
        .help(changes.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(changes.summary)
        .animation(Theme.Motion.content, value: changes)
    }

    @ViewBuilder
    private func count(_ sign: String, _ value: Int, _ color: Color) -> some View {
        if value > 0 {
            Text("\(sign)\(value)")
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
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
