import SwiftUI

/// The Insights card: what Claude Code cost and did over the last 24 hours,
/// 7 days, 30 days, 3 months, 6 months or year, with a bar per hour, day,
/// week or month, the busiest projects and the split by model. Hovering a bar
/// shows that bar's numbers.
struct InsightsWidgetView: View {
    let monitor: InsightsMonitor
    @Bindable var settings: AppSettings

    /// The bar under the pointer.
    @State private var hoveredBar: Int?

    init(monitor: InsightsMonitor, settings: AppSettings, hoveredBar: Int? = nil) {
        self.monitor = monitor
        self.settings = settings
        _hoveredBar = State(initialValue: hoveredBar)
    }

    private var range: InsightsRange { settings.insightsRange }
    private var summary: InsightsSummary? { monitor.summary(for: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let summary, !summary.isEmpty {
                headline(summary)
                chart(summary)
                stats(summary)
                Rectangle().fill(Theme.Palette.hairline).frame(height: 0.5)
                breakdown(summary)
            } else if let error = monitor.loadError {
                note(error)
            } else if monitor.isLoading || summary == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    note("Reading Claude Code's history…")
                }
            } else {
                note("No Claude Code activity in the \(range.spoken).")
            }
        }
        .animation(Theme.Motion.content, value: summary)
        .animation(Theme.Motion.content, value: range)
        .widgetCard()
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Label("Insights", systemImage: "chart.bar.xaxis")
                .font(Theme.Typeface.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(InsightsRange.allCases) { chip($0) }
            }
        }
    }

    private func chip(_ option: InsightsRange) -> some View {
        let isOn = option == range
        return Button {
            hoveredBar = nil
            withAnimation(Theme.Motion.content) { settings.insightsRange = option }
        } label: {
            Text(option.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOn ? Theme.Palette.clay : Theme.Palette.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Theme.Palette.clay.opacity(0.14) : Color.white.opacity(0.05)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show the \(option.spoken)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Headline

    private func headline(_ summary: InsightsSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(InsightsFormat.cost(summary.cost))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                HStack(spacing: 3) {
                    Text(costCaption(summary))
                    InfoButton(
                        text: "What these tokens would cost at Anthropic's **API list prices**, cache reads and writes included.\n\nOn a Pro or Max plan you pay your subscription, not this. Worked out from Claude Code's transcripts in **~/.claude/projects**." + (summary.hasUnpricedReplies ? "\n\nSome replies came from a model without a list price; their tokens are counted, their cost isn't." : ""),
                        title: "Cost",
                        tint: Theme.Palette.textTertiary
                    )
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(InsightsFormat.tokens(summary.tokens.total))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(tokensCaption(summary))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "at API prices", plus the daily average over anything longer than a day.
    private func costCaption(_ summary: InsightsSummary) -> String {
        guard range != .day else { return "at API prices" }
        return "at API prices · \(InsightsFormat.cost(summary.cost / Double(summary.dayCount)))/day"
    }

    private func tokensCaption(_ summary: InsightsSummary) -> String {
        guard let hit = summary.cacheHitRate else { return "tokens" }
        return "tokens · \(Int((hit * 100).rounded()))% cached"
    }

    // MARK: Chart

    private func chart(_ summary: InsightsSummary) -> some View {
        let buckets = summary.buckets
        // Cost when there is one; a model without a price still shows its tokens.
        let usesCost = summary.cost > 0
        let values = buckets.map { usesCost ? $0.cost : Double($0.tokens) }
        let peak = max(values.max() ?? 0, .leastNonzeroMagnitude)

        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: range == .day ? 3 : 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        bar(fraction: value / peak, isHovered: hoveredBar == index, dims: hoveredBar != nil)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let index = Int(point.x / max(proxy.size.width, 1) * CGFloat(values.count))
                        hoveredBar = min(max(index, 0), values.count - 1)
                    case .ended:
                        hoveredBar = nil
                    }
                }
            }
            .frame(height: 48)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chartDescription(summary))

            if let hoveredBar, buckets.indices.contains(hoveredBar) {
                hoverLine(buckets[hoveredBar])
            } else if range == .week || range == .year {
                barLabels(buckets)
            } else {
                axis
            }

            if let begins = summary.historyBegins {
                historyNote(begins)
            }
        }
    }

    private func bar(fraction: Double, isHovered: Bool, dims: Bool) -> some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fraction > 0
                          ? (isHovered ? Theme.Palette.clayGlow : Theme.Palette.clay.opacity(dims ? 0.45 : 0.85))
                          : Theme.Palette.surfaceRaised)
                    // Quiet hours keep a sliver, so the timeline reads as continuous.
                    .frame(height: fraction > 0 ? max(3, proxy.size.height * fraction) : 2)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var axis: some View {
        HStack {
            Text(axisStart)
            Spacer()
            Text(axisEnd)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    /// A label under each bar: the week's days, or the year's months.
    private func barLabels(_ buckets: [InsightsSummary.Bucket]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                Text(barLabel(bucket.start, isLast: index == buckets.count - 1))
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func barLabel(_ start: Date, isLast: Bool) -> String {
        if range == .year { return start.formatted(.dateTime.month(.abbreviated)) }
        return isLast ? "Today" : start.formatted(.dateTime.weekday(.abbreviated))
    }

    private var axisStart: String {
        switch range {
        case .day: return "24 hours ago"
        case .week: return "7 days ago"
        case .month: return "30 days ago"
        case .quarter: return "3 months ago"
        case .half: return "6 months ago"
        case .year: return "12 months ago"
        }
    }

    private var axisEnd: String {
        switch range {
        case .day: return "Now"
        case .week, .month: return "Today"
        case .quarter, .half: return "This week"
        case .year: return "This month"
        }
    }

    /// Claude Code deletes old transcripts, so a long range may reach further back than there's history for.
    private func historyNote(_ begins: Date) -> some View {
        HStack(spacing: 3) {
            Text("History only goes back to \(begins.formatted(.dateTime.day().month(.abbreviated).year()))")
            InfoButton(
                text: "Claude Code deletes transcripts older than **30 days** by default, so there's nothing earlier to count.\n\nTo keep more, set **cleanupPeriodDays** in **~/.claude/settings.json**, e.g. `\"cleanupPeriodDays\": 365`. Transcripts already deleted can't be brought back.",
                title: "History",
                tint: Theme.Palette.textTertiary
            )
        }
        .font(.system(size: 9.5))
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func hoverLine(_ bucket: InsightsSummary.Bucket) -> some View {
        HStack(spacing: 6) {
            Text(bucketTitle(bucket.start))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(InsightsFormat.cost(bucket.cost))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("·")
            Text("\(InsightsFormat.tokens(bucket.tokens)) tokens")
            Text("·")
            Text(bucket.replies == 1 ? "1 reply" : "\(bucket.replies) replies")
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func bucketTitle(_ start: Date) -> String {
        switch range {
        case .day:
            let end = start.addingTimeInterval(3600)
            return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        case .week, .month:
            return start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .quarter, .half:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .year:
            return start.formatted(.dateTime.month(.wide).year())
        }
    }

    private func chartDescription(_ summary: InsightsSummary) -> String {
        guard let peak = summary.peakBucket, peak.cost > 0 else { return "No activity to chart" }
        return "Busiest: \(bucketTitle(peak.start)), \(InsightsFormat.cost(peak.cost))"
    }

    // MARK: Stats

    private func stats(_ summary: InsightsSummary) -> some View {
        HStack(spacing: 8) {
            stat("Sessions", "\(summary.sessions)", symbol: "rectangle.stack")
            stat("Active", InsightsFormat.duration(summary.activeTime), symbol: "timer",
                 info: "Time Claude was working: the gaps of up to five minutes between a session's prompts and replies, added up.")
            stat("Prompts", "\(summary.prompts)", symbol: "text.bubble")
            stat("Files", "\(summary.filesChanged)", symbol: "doc.badge.ellipsis",
                 info: "Different files Claude edited or wrote (Edit, Write, MultiEdit, NotebookEdit).")
        }
    }

    private func stat(_ title: String, _ value: String, symbol: String, info: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                if let info {
                    InfoButton(text: info, title: title, tint: Theme.Palette.textTertiary)
                        .padding(.leading, -2)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.Palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    // MARK: Breakdown

    private func breakdown(_ summary: InsightsSummary) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle("Projects")
                let top = Array(summary.projects.prefix(3))
                let most = max(top.first?.cost ?? 0, .leastNonzeroMagnitude)
                ForEach(top, id: \.name) { project in
                    projectRow(project, fraction: project.cost / most)
                }
                if summary.projects.count > 3 {
                    Text("+ \(summary.projects.count - 3) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                sectionTitle("Models")
                ModelSplitBar(models: summary.models, total: summary.cost)
                ForEach(summary.models.prefix(4), id: \.name) { model in
                    modelRow(model, total: summary.cost)
                }
            }
            .frame(width: 150, alignment: .leading)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.micro)
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func projectRow(_ project: InsightsSummary.Share, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(InsightsFormat.cost(project.cost))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            UsageBar(fraction: fraction, tint: Theme.Palette.clay.opacity(0.8))
                .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
    }

    private func modelRow(_ model: InsightsSummary.Share, total: Double) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ModelSplitBar.tint(for: model.name))
                .frame(width: 6, height: 6)
            Text(model.name)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 4)
            Text(total > 0 ? "\(Int((model.cost / total * 100).rounded()))%" : InsightsFormat.tokens(model.tokens))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One bar split by each model's share of the cost.
private struct ModelSplitBar: View {
    let models: [InsightsSummary.Share]
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            let shown = models.filter { $0.cost > 0 }
            let gaps = CGFloat(max(shown.count - 1, 0)) * 2
            let width = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(shown, id: \.name) { model in
                    Capsule()
                        .fill(Self.tint(for: model.name))
                        .frame(width: max(proxy.size.height, width * model.cost / max(total, .leastNonzeroMagnitude)))
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    static func tint(for family: String) -> Color {
        switch family {
        case ModelFamily.fable.title: return Color(hex: 0xA48BE0)
        case ModelFamily.opus.title: return Theme.Palette.clay
        case ModelFamily.sonnet.title: return Color(hex: 0x6FA8DC)
        case ModelFamily.haiku.title: return Theme.Palette.success
        default: return Theme.Palette.textTertiary
        }
    }
}

/// Short numbers for a small card.
enum InsightsFormat {
    /// "$0.42", "$25.40", "$1,018".
    static func cost(_ value: Double) -> String {
        value >= 1000
            ? value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
            : value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// "820", "12.4K", "63.8M", "2.58B".
    static func tokens(_ value: Int) -> String {
        let number = Double(value)
        switch value {
        case 1_000_000_000...: return (number / 1_000_000_000).formatted(.number.precision(.fractionLength(0...2))) + "B"
        case 1_000_000...: return (number / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        case 1000...: return (number / 1000).formatted(.number.precision(.fractionLength(0...1))) + "K"
        default: return "\(value)"
        }
    }

    /// "0m", "45m", "2h 16m", "59h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return hours >= 10 || rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
