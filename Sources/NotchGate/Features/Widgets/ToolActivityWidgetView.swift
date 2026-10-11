import SwiftUI

/// The Tools card: which tools Claude has called this session (Bash, Edit,
/// Read…) as a split bar with counts, and a heat strip of calls over the last
/// hour. With several sessions, chips pick one or show them all together.
struct ToolActivityWidgetView: View {
    struct Entry: Identifiable, Equatable {
        /// Claude Code session id.
        let id: String
        let name: String
        let usage: ToolUsage
    }

    /// Sessions in the activity list, most relevant first.
    let entries: [Entry]

    /// The chosen session; `nil` is every session together.
    @State private var selection: String?

    /// The heat strip: 30 cells of 2 minutes, the last hour.
    static let buckets = 30
    static let bucketMinutes = 2

    var body: some View {
        // The heat strip slides along on its own between tool calls.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .widgetCard()
    }

    private func content(now: Date) -> some View {
        let usage = shownUsage
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "hammer")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                Spacer()
                if !usage.isEmpty {
                    Text(usage.total == 1 ? "1 call" : "\(usage.total) calls")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .contentTransition(.numericText())
                }
            }

            if entries.count > 1 { picker }

            if usage.isEmpty {
                Text(entries.isEmpty ? "Appears once Claude Code runs a tool." : "No tools called yet this session.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                ToolSplitBar(ranked: usage.ranked, total: usage.total)
                legend(usage.ranked)
                heatStrip(usage.timeline(endingAt: now, buckets: Self.buckets, bucketMinutes: Self.bucketMinutes))
            }
        }
        .animation(Theme.Motion.content, value: usage)
        .animation(Theme.Motion.content, value: selectedID)
    }

    // MARK: Selection

    /// The chosen session while it's still listed; otherwise every session.
    private var selectedID: String? {
        guard let selection, entries.contains(where: { $0.id == selection }) else { return nil }
        return selection
    }

    private var shownUsage: ToolUsage {
        if entries.count == 1 { return entries[0].usage }
        if let id = selectedID, let entry = entries.first(where: { $0.id == id }) { return entry.usage }
        return .combined(entries.map(\.usage))
    }

    private var title: String {
        if entries.count == 1 { return "Tools · \(entries[0].name)" }
        if let id = selectedID, let entry = entries.first(where: { $0.id == id }) { return "Tools · \(entry.name)" }
        return "Tools"
    }

    private var picker: some View {
        HStack(spacing: 4) {
            chip("All", id: nil)
            ForEach(entries) { chip($0.name, id: $0.id) }
        }
    }

    private func chip(_ label: String, id: String?) -> some View {
        let isOn = selectedID == id
        return Button {
            withAnimation(Theme.Motion.content) { selection = id }
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOn ? Theme.Palette.clay : Theme.Palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Theme.Palette.clay.opacity(0.14) : Color.white.opacity(0.05)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(id == nil ? "Every session together" : "Only \(label)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Breakdown

    /// Each category used: a dot in its colour, its name and its count, two to a row.
    private func legend(_ ranked: [(category: ToolUsage.Category, count: Int)]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(ranked, id: \.category) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.category.tint)
                        .frame(width: 6, height: 6)
                    Image(systemName: item.category.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(width: 12)
                    Text(item.category.title)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(item.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.category.title): \(item.count) \(item.count == 1 ? "call" : "calls")")
            }
        }
    }

    /// Calls in each 2-minute span of the last hour; brighter is busier.
    private func heatStrip(_ timeline: [Int]) -> some View {
        let peak = max(timeline.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(timeline.enumerated()), id: \.offset) { _, calls in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(calls == 0 ? Theme.Palette.surfaceRaised : Theme.Palette.clay.opacity(0.25 + 0.75 * Double(calls) / Double(peak)))
                        .frame(height: 10)
                }
            }
            HStack {
                Text("1 hour ago")
                Spacer()
                Text("Now")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.Palette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timeline.reduce(0, +)) tool calls in the last hour")
    }
}

/// One bar split by category, widest first.
private struct ToolSplitBar: View {
    let ranked: [(category: ToolUsage.Category, count: Int)]
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(ranked.count - 1, 0)) * 2
            let width = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(ranked, id: \.category) { item in
                    // Rare tools keep a sliver, so they never vanish next to a busy one.
                    Capsule()
                        .fill(item.category.tint)
                        .frame(width: max(proxy.size.height, width * CGFloat(item.count) / CGFloat(max(total, 1))))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

extension ToolUsage.Category {
    /// Distinct on the island's black, led by the brand clay for shell commands.
    var tint: Color {
        switch self {
        case .run: return Theme.Palette.clay
        case .edit: return Theme.Palette.success
        case .read: return Color(hex: 0x6FA8DC)
        case .search: return Theme.Palette.warning
        case .web: return Color(hex: 0xA48BE0)
        case .agent: return Color(hex: 0xE08BB5)
        case .mcp: return Color(hex: 0x5FC4C4)
        case .other: return Theme.Palette.textTertiary
        }
    }
}
