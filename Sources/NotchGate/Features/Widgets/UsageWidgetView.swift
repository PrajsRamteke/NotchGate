import NotchGateKit
import SwiftUI

/// Glanceable widgets at the top of the hover panel. Each is switched on in
/// the menu bar's Widgets section and opened from its header button; new
/// widgets get a line here.
struct NotchWidgetsView: View {
    let usage: UsageMonitor

    var body: some View {
        if usage.isEnabled, usage.settings.usageCardShown {
            UsageWidgetView(snapshot: usage.snapshot)
        }
    }
}

/// The plan's 5-hour and weekly limits side by side, with when each resets.
struct UsageWidgetView: View {
    let snapshot: UsageSnapshot?

    var body: some View {
        // Reset countdowns and "updated" age move on their own between snapshots.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
        )
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Usage", systemImage: "gauge.with.dots.needle.50percent")
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
                HStack(alignment: .top, spacing: 16) {
                    UsageGaugeView(gauge: .fiveHour(snapshot, now: now))
                    UsageGaugeView(gauge: .weekly(snapshot, now: now))
                }
            } else {
                Text("Appears after Claude Code's next reply. Needs a Pro or Max plan.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Title and percentage, a thin bar, and the reset time underneath.
private struct UsageGaugeView: View {
    let gauge: UsageGauge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.title)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: 6)
                Text("\(gauge.percent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(gauge.level == .normal ? Theme.Palette.textPrimary : tint)
                    .contentTransition(.numericText())
            }
            UsageBar(fraction: gauge.fraction, tint: tint)
            Text(gauge.resetText)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.content, value: gauge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gauge.title), \(gauge.percent) percent used. \(gauge.resetText).")
    }

    private var tint: Color {
        switch gauge.level {
        case .normal: return Theme.Palette.clay
        case .high: return Theme.Palette.warning
        case .critical: return Theme.Palette.danger
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.surfaceRaised)
                if fraction > 0 {
                    // A sliver stays visible at 1%, so "some" never reads as "none".
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.height, proxy.size.width * min(fraction, 1)))
                }
            }
        }
        .frame(height: 5)
    }
}
