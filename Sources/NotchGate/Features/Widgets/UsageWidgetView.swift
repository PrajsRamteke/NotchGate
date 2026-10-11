import NotchGateKit
import SwiftUI

/// Glanceable widgets at the top of the hover panel. Each is switched on in
/// the menu bar's Widgets section and opened from its header button; new
/// widgets get a line here.
struct NotchWidgetsView: View {
    let usage: UsageMonitor
    let session: SessionMonitor
    /// Sessions in the activity list, newest first; the Session card follows them.
    let sessions: [SessionActivity]

    // No wrapping stack: each card joins the panel's stack on its own, so a
    // hidden card leaves no gap and each one animates in separately.
    var body: some View {
        if usage.isEnabled, usage.settings.usageCardShown {
            UsageWidgetView(snapshot: usage.snapshot)
        }
        if session.isEnabled, session.settings.sessionCardShown {
            SessionWidgetView(entries: sessionEntries)
        }
    }

    /// The running sessions that have reported, or else the last one that did,
    /// so the card isn't blank between sessions.
    private var sessionEntries: [SessionWidgetView.Entry] {
        let live = sessions.compactMap { activity in
            session.snapshot(for: activity.id).map {
                SessionWidgetView.Entry(id: activity.id, name: activity.projectName, snapshot: $0)
            }
        }
        if !live.isEmpty { return live }
        return session.latest.map {
            [SessionWidgetView.Entry(id: $0.sessionID, name: $0.projectName ?? "Claude Code", snapshot: $0)]
        } ?? []
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
        .widgetCard()
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

/// The card look shared by the notch's widgets.
extension View {
    func widgetCard() -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
            )
    }
}

struct UsageBar: View {
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
