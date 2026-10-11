import SwiftUI

/// Serif title with an optional secondary line — the voice of every card.
struct CardTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typeface.title)
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trailing-aligned row of actions with an optional leading accessory.
struct ActionRow<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 0)
            actions
        }
        .padding(.top, 2)
    }
}

extension ActionRow where Leading == EmptyView {
    init(@ViewBuilder actions: () -> Actions) {
        self.leading = EmptyView()
        self.actions = actions()
    }
}

/// Small underlined text action for secondary paths ("Add a note…").
struct LinkButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.Typeface.caption)
            .foregroundStyle(isHovered ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            .onHover { isHovered = $0 }
    }
}

/// Scroll container that hugs its content until it reaches `maxHeight`,
/// then scrolls. Measures the content so short previews never leave a gap.
struct CappedScroll<Content: View>: View {
    var axes: Axis.Set = .vertical
    var maxHeight: CGFloat = Theme.Metrics.expandedMaxContentHeight
    /// When set, the child with this `.id` is scrolled fully into view.
    var scrollTarget: String?
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axes, showsIndicators: false) {
                content
                    // Horizontal scroll views center narrow content; keep it leading.
                    .frame(minWidth: axes.contains(.horizontal) ? viewportWidth : nil, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // Wait for the dropdown to open before scrolling to its end.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(Theme.Motion.content) { proxy.scrollTo(target, anchor: .bottom) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { viewportWidth = $0 })
        .frame(height: min(contentHeight, maxHeight))
    }
}
