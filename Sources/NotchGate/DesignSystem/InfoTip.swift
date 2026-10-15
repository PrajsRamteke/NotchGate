import AppKit
import SwiftUI

/// A small ⓘ beside a setting. Hovering it (or clicking it) shows what the
/// setting does in a bubble drawn by the nearest `.infoTipHost()`, so the row
/// itself can stay a single clean line.
struct InfoButton: View {
    /// What the bubble explains. Inline Markdown (`**bold**`) and line breaks work.
    let text: String
    /// The setting it belongs to, for VoiceOver ("About Auto-allow permissions").
    var title: String?
    /// Icon colour on the always-dark island; the menu uses the system's.
    var tint: Color?

    @State private var isHovered = false
    @State private var isShowing = false
    @State private var pendingShow: Task<Void, Never>?
    @Environment(\.infoTipPreview) private var preview

    var body: some View {
        Image(systemName: isShowing ? "info.circle.fill" : "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(iconStyle)
            .frame(width: 16, height: 16)
            .contentShape(Circle())
            .onHover(perform: hover)
            // A pointer click comes while hovering, so it only ever opens.
            .onTapGesture {
                pendingShow?.cancel()
                isShowing = true
            }
            .onDisappear { pendingShow?.cancel() }
            .anchorPreference(key: InfoTipKey.self, value: .bounds) { anchor in
                isShowing || isPreviewed ? [InfoTip(text: text, anchor: anchor)] : []
            }
            .accessibilityElement()
            .accessibilityLabel(title.map { "About \($0)" } ?? "More info")
            .accessibilityValue(Text(InfoTip.attributed(text)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isShowing.toggle() }
    }

    private var isPreviewed: Bool { preview != nil && preview == title }

    private var iconStyle: AnyShapeStyle {
        let lit = isHovered || isShowing || isPreviewed
        if let tint { return AnyShapeStyle(lit ? tint.opacity(1) : tint.opacity(0.7)) }
        return lit ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    /// A short pause before showing, so sweeping the pointer across a list
    /// doesn't flash every bubble; leaving hides it straight away.
    private func hover(_ hovering: Bool) {
        isHovered = hovering
        pendingShow?.cancel()
        guard hovering else {
            isShowing = false
            return
        }
        pendingShow = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isShowing = true
        }
    }
}

/// Where a bubble is drawn: the system-themed menu or the dark island.
enum InfoTipStyle {
    case menu
    case island
}

extension View {
    /// Draws the bubble for any `InfoButton` inside, on top of everything,
    /// so scroll views and cards don't clip it.
    func infoTipHost(_ style: InfoTipStyle = .menu) -> some View {
        overlayPreferenceValue(InfoTipKey.self) { tips in
            GeometryReader { proxy in
                if let tip = tips.last {
                    InfoTipBubble(tip: tip, style: style, container: proxy)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.14), value: tips.last?.text)
        }
    }
}

extension EnvironmentValues {
    /// Snapshots: the title of the setting whose bubble is shown open.
    @Entry var infoTipPreview: String?
}

struct InfoTip: Equatable {
    let text: String
    let anchor: Anchor<CGRect>

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct InfoTipKey: PreferenceKey {
    static let defaultValue: [InfoTip] = []
    static func reduce(value: inout [InfoTip], nextValue: () -> [InfoTip]) {
        value.append(contentsOf: nextValue())
    }
}

/// The bubble itself: centred under its ⓘ (or above it, near the bottom),
/// kept inside the host's bounds.
private struct InfoTipBubble: View {
    let tip: InfoTip
    let style: InfoTipStyle
    let container: GeometryProxy

    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8

    var body: some View {
        let icon = container[tip.anchor]
        let size = container.size
        let width = min(style == .menu ? 248 : 280, size.width - Self.margin * 2)
        let x = min(max(icon.midX - width / 2, Self.margin), size.width - width - Self.margin)
        let spaceBelow = size.height - icon.maxY
        let below = spaceBelow >= 110 || spaceBelow >= icon.minY

        ZStack(alignment: .topLeading) {
            if below {
                bubble(width: width)
                    .offset(x: x, y: icon.maxY + Self.gap)
            } else {
                bubble(width: width)
                    .frame(height: max(0, icon.minY - Self.gap), alignment: .bottom)
                    .offset(x: x)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: below ? .top : .bottom)))
    }

    private func bubble(width: CGFloat) -> some View {
        Text(InfoTip.attributed(tip.text))
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundStyle(style == .island ? AnyShapeStyle(Theme.Palette.textPrimary) : AnyShapeStyle(.primary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(style == .island ? Color.white.opacity(0.12) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    private var background: Color {
        switch style {
        case .island: return Color(hex: 0x2A2A2D)
        case .menu: return Self.menuBackground
        }
    }

    /// A step up from the menu's own background in either appearance.
    private static let menuBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.19, alpha: 1)
            : NSColor(white: 1, alpha: 1)
    })
}
