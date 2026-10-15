import SwiftUI

/// A menu section whose heading toggles it open or closed (chevron on the
/// right). The choice is remembered; closed sections show a short summary.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let symbol: String
    let summary: String?
    @AppStorage private var isExpanded: Bool
    private let content: Content

    @State private var isHovered = false
    @Environment(\.expandsAllMenuSections) private var expandsAll

    init(
        _ title: String,
        symbol: String,
        id: String,
        expandedByDefault: Bool = false,
        summary: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self._isExpanded = AppStorage(wrappedValue: expandedByDefault, "menuSection.\(id)")
        self.content = content()
    }

    private var isOpen: Bool { isExpanded || expandsAll }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOpen ? Theme.Palette.clay : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isOpen ? Theme.Palette.clay.opacity(0.16) : Color.primary.opacity(0.07))
                        )
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 8)
                    if !isOpen, let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .secondary : .tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(title), \(isOpen ? "expanded" : "collapsed")")
            .accessibilityHint("Shows or hides these settings")

            if isOpen {
                content
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Clip the open/close slide, leaving room for the header's hover fill.
        .clipShape(Rectangle().inset(by: -8))
    }
}

extension EnvironmentValues {
    /// Opens every section regardless of the remembered choice (snapshots).
    @Entry var expandsAllMenuSections = false
}
