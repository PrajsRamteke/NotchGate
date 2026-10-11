import SwiftUI

/// The bot's comic-style speech bubble: a bold line, then today's progress.
struct WaterBotBubble: View {
    let title: String
    /// Replaces the droplet row when set (e.g. "Back in 10 min").
    let detail: String?
    let glasses: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(WaterBotFigure.Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .id(title)
                .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WaterBotFigure.Palette.ink.opacity(0.6))
            } else {
                progress
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10 + BubbleShape.tail)
        .frame(width: 178, alignment: .leading)
        .background {
            BubbleShape()
                .fill(LinearGradient(colors: [.white, Theme.Palette.ivory], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.Palette.clay.opacity(0.55), radius: 10)
        }
        .overlay(BubbleShape().stroke(Theme.Palette.clay, lineWidth: 2.2))
        .contentShape(BubbleShape())
        .accessibilityElement(children: .combine)
    }

    /// One droplet per glass of today's goal (or a count, for big goals).
    @ViewBuilder
    private var progress: some View {
        if goal <= 12 {
            HStack(spacing: 2.5) {
                ForEach(0..<goal, id: \.self) { index in
                    Image(systemName: index < glasses ? "drop.fill" : "drop")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(index < glasses ? Theme.Palette.clay : WaterBotFigure.Palette.ink.opacity(0.25))
                }
            }
            .accessibilityLabel("\(glasses) of \(goal) glasses today")
        } else {
            Text("\(glasses) of \(goal) glasses today")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WaterBotFigure.Palette.ink.opacity(0.6))
        }
    }
}

/// Rounded rectangle with a tail on the lower left, pointing back at the bot.
struct BubbleShape: Shape {
    static let tail: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.tail)
        var path = Path(roundedRect: body, cornerRadius: 18, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: body.minX + 22, y: body.maxY - 1))
        tail.addQuadCurve(to: CGPoint(x: body.minX - 6, y: rect.maxY), control: CGPoint(x: body.minX + 16, y: rect.maxY - 2))
        tail.addQuadCurve(to: CGPoint(x: body.minX + 42, y: body.maxY - 1), control: CGPoint(x: body.minX + 26, y: rect.maxY - 4))
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}
