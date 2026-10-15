import SwiftUI

/// Root of the panel: a transparent canvas with the island pinned to the
/// top-center. Size, silhouette and content all morph on one spring.
struct IslandRootView: View {
    @Bindable var model: IslandViewModel

    var body: some View {
        ZStack(alignment: .top) {
            // Behind the island, so the bot's rope comes out from under the notch.
            WaterBotStage(model: model)
            VStack(spacing: 0) {
                island
                Spacer(minLength: 0)
            }
        }
        .frame(width: Theme.Metrics.canvasSize.width, height: Theme.Metrics.canvasSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var presentation: IslandPresentation { model.presentation }
    private var shape: NotchShape { .forPresentation(presentation) }

    private var island: some View {
        VStack(spacing: 0) {
            IslandStatusBar(model: model)
                .frame(height: model.notch.notchSize.height)

            if presentation == .expanded {
                ExpandedIslandView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                            .animation(Theme.Motion.content.delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.12))
                    ))
            }
        }
        .padding(.horizontal, shape.topRadius)
        .frame(width: islandWidth)
        .background(IslandBackground(shape: shape, isActive: model.store.hasPending))
        .clipShape(shape)
        .shadow(color: .black.opacity(presentation == .expanded ? 0.55 : 0), radius: 28, y: 14)
        .opacity(presentation == .hidden && !model.notch.hasNotch ? 0 : 1)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { model.islandFrame = $0 })
        .animation(presentation == .expanded ? Theme.Motion.expand : Theme.Motion.collapse, value: presentation)
        .animation(Theme.Motion.expand, value: model.store.current?.id)
    }

    private var islandWidth: CGFloat {
        let notchWidth = model.notch.notchSize.width + shape.topRadius * 2
        switch presentation {
        case .hidden: return notchWidth
        case .peek:
            let wing = model.showsNowPlayingPeek ? Theme.Metrics.musicWingWidth : Theme.Metrics.peekWingWidth
            return notchWidth + wing * 2
        case .expanded: return max(Theme.Metrics.expandedWidth, notchWidth + Theme.Metrics.peekWingWidth * 2)
        }
    }
}

/// Pure black body with a faint clay aura (bottom-left) while Claude is waiting, plus a
/// hairline rim light along the lower edge for depth.
private struct IslandBackground: View {
    let shape: NotchShape
    let isActive: Bool

    var body: some View {
        ZStack {
            shape.fill(Theme.Palette.island)
            RadialGradient(
                colors: [Theme.Palette.clay.opacity(0.16), .clear],
                // Glow rises from the bottom-left so the top stays pure black
                // and blends seamlessly into the hardware notch.
                center: .init(x: 0.06, y: 1.0),
                startRadius: 0,
                endRadius: 260
            )
            .clipShape(shape)
            // Scoped to the glow's opacity on purpose. An `.animation(_:value:)`
            // here would also retime the background's size and silhouette, and a
            // request arriving flips `isActive` as the island expands: the black
            // fill would then grow slower than the clip, leaving the card's text
            // briefly drawn over nothing.
            .animation(.easeInOut(duration: 0.6)) { $0.opacity(isActive ? 1 : 0) }
            shape.stroke(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.10)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
    }
}
