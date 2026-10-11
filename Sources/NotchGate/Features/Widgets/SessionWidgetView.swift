import NotchGateKit
import SwiftUI

/// The Session card at the top of the hover panel. With one session it shows
/// that session in full; with several, a line each (project, model, context,
/// cost) and their total cost. Each session row's own button opens its full
/// details there.
struct SessionWidgetView: View {
    struct Entry: Identifiable, Equatable {
        /// Claude Code session id.
        let id: String
        let name: String
        let snapshot: SessionSnapshot
    }

    let entries: [Entry]

    var body: some View {
        // The "updated" age moves on its own between snapshots.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .widgetCard()
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "cpu")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                Spacer()
                if let newest = entries.map(\.snapshot.updatedAt).max() {
                    Text(UsageGauge.updatedPhrase(newest, now: now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            switch entries.count {
            case 0:
                Text("Appears after Claude Code's next reply.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Palette.textTertiary)
            case 1:
                SessionUsageDetails(snapshot: entries[0].snapshot)
            default:
                VStack(spacing: 8) {
                    ForEach(entries) { SessionUsageLine(entry: $0) }
                }
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 0.5)
                total
            }
        }
    }

    private var title: String {
        switch entries.count {
        case 0: return "Session"
        case 1: return "Session · \(entries[0].name)"
        default: return "Sessions"
        }
    }

    /// What the listed sessions have cost together.
    private var total: some View {
        let costs = entries.compactMap(\.snapshot.costUSD)
        return HStack(alignment: .firstTextBaseline) {
            Text("Total cost")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 6)
            Text(SessionUsageDetails.costPhrase(costs.isEmpty ? nil : costs.reduce(0, +)))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
        }
    }
}

/// One session in the Session card's list: project, model, context and cost on a line.
private struct SessionUsageLine: View {
    let entry: SessionWidgetView.Entry

    var body: some View {
        let snapshot = entry.snapshot
        HStack(spacing: 8) {
            Text(entry.name)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            if let model = snapshot.model {
                Text(model)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let percent = snapshot.contextPercent {
                UsageBar(fraction: percent / 100, tint: SessionUsageDetails.tint(for: percent))
                    .frame(width: 40)
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            Text(SessionUsageDetails.costPhrase(snapshot.costUSD))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .help(snapshot.branch.map { "\(entry.name) on \($0)" } ?? entry.name)
        .accessibilityElement(children: .combine)
    }
}

/// One session in full: model and branch, how full the context window is,
/// and what it has cost so far. Used by the Session card and each session row.
struct SessionUsageDetails: View {
    let snapshot: SessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.model != nil || snapshot.branch != nil {
                HStack(spacing: 6) {
                    if let model = snapshot.model {
                        chip(model, systemImage: "sparkle")
                            .layoutPriority(1)
                    }
                    if let branch = snapshot.branch {
                        // Long branch names keep their prefix and ticket suffix.
                        chip(branch, systemImage: "arrow.triangle.branch")
                            .truncationMode(.middle)
                            .help(branch)
                    }
                    Spacer(minLength: 0)
                }
            }

            contextGauge

            HStack(alignment: .firstTextBaseline) {
                Text("Cost")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 6)
                Text(Self.costPhrase(snapshot.costUSD))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
            }
        }
    }

    /// Context fill as a percentage of the window, with a bar that warms as it fills.
    @ViewBuilder
    private var contextGauge: some View {
        if let percent = snapshot.contextPercent {
            let rounded = Int(percent.rounded())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Context")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 6)
                    Text("\(rounded)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rounded >= 75 ? Self.tint(for: percent) : Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    if let size = snapshot.contextSize {
                        Text("of \(Self.tokenPhrase(size))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                UsageBar(fraction: percent / 100, tint: Self.tint(for: percent))
            }
            .animation(Theme.Motion.content, value: rounded)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Context \(rounded) percent used")
        }
    }

    static func tint(for percent: Double) -> Color {
        percent >= 90 ? Theme.Palette.danger : percent >= 75 ? Theme.Palette.warning : Theme.Palette.clay
    }

    /// "$1.24", or "—" before Claude Code has reported a cost.
    static func costPhrase(_ cost: Double?) -> String {
        cost.map { $0.formatted(.currency(code: "USD")) } ?? "—"
    }

    /// "200K", "1M", "1.5M": the window size in tokens, shortened.
    static func tokenPhrase(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...:
            return (Double(tokens) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        case 1000...: return "\(tokens / 1000)K"
        default: return "\(tokens)"
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        // Not `micro`: its small caps would misspell case-sensitive branch names.
        Label(text, systemImage: systemImage)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
