import NotchGateKit
import SwiftUI

/// The latest session at a glance: its model and branch, how full the context
/// window is, and what it has cost so far.
struct SessionWidgetView: View {
    let snapshot: SessionSnapshot?

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
                Label("Session", systemImage: "cpu")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                if let snapshot {
                    Text(UsageGauge.updatedPhrase(snapshot.updatedAt, now: now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }

            if let snapshot {
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

                contextGauge(snapshot)

                HStack(alignment: .firstTextBaseline) {
                    Text("Cost")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 6)
                    Text(snapshot.costUSD.map { $0.formatted(.currency(code: "USD")) } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                }
            } else {
                Text("Appears after Claude Code's next reply.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    /// Context fill as a percentage of the window, with a bar that warms as it fills.
    @ViewBuilder
    private func contextGauge(_ snapshot: SessionSnapshot) -> some View {
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
                        .foregroundStyle(rounded >= 75 ? tint(for: percent) : Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    if let size = snapshot.contextSize {
                        Text("of \(Self.tokenPhrase(size))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                UsageBar(fraction: percent / 100, tint: tint(for: percent))
            }
            .animation(Theme.Motion.content, value: rounded)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Context \(rounded) percent used")
        }
    }

    private func tint(for percent: Double) -> Color {
        percent >= 90 ? Theme.Palette.danger : percent >= 75 ? Theme.Palette.warning : Theme.Palette.clay
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
        Label(text, systemImage: systemImage)
            .font(Theme.Typeface.micro)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
