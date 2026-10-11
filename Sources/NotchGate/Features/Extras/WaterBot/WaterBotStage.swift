import SwiftUI

/// The strip of screen under the notch where the water bot hangs. It's
/// clipped at the notch's lower edge, so the bot appears to drop out of the
/// notch on its rope and climb back into it.
struct WaterBotStage: View {
    let model: IslandViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if model.showsWaterBot {
                WaterBotView(
                    water: model.water,
                    isHovered: model.isHoveringWaterBot,
                    onHitAreaChange: { model.waterBotFrame = $0 }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).animation(.spring(response: 0.62, dampingFraction: 0.58)),
                    removal: .move(edge: .top).animation(.easeIn(duration: 0.42))
                ))
            }
        }
        .frame(width: WaterBotView.size.width, height: WaterBotView.size.height, alignment: .top)
        .clipped()
        // Tucked a hair under the notch so the rope starts behind it.
        .padding(.top, model.notch.notchSize.height - 2)
        .animation(.spring(response: 0.62, dampingFraction: 0.58), value: model.showsWaterBot)
    }
}
