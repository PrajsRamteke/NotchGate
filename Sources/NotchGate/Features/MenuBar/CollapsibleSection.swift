import SwiftUI

/// A menu section whose heading toggles it open or closed (chevron on the
/// right). The choice is remembered; closed sections show a short summary.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let summary: String?
    @AppStorage private var isExpanded: Bool
    private let content: Content

    @State private var isHovered = false

    init(
        _ title: String,
        id: String,
        expandedByDefault: Bool = false,
        summary: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self._isExpanded = AppStorage(wrappedValue: expandedByDefault, "menuSection.\(id)")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SectionLabel(title)
                        .fixedSize()
                    Spacer(minLength: 8)
                    if !isExpanded, let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Shows or hides these settings")

            if isExpanded {
                content.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}
