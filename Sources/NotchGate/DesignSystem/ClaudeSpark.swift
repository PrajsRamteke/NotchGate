import SwiftUI

/// A radial starburst glyph evoking Claude's mark: tapered rays of
/// alternating length radiating from a soft center.
struct SparkShape: Shape {
    var rays = 12
    var innerRatio: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for index in 0..<rays {
            let angle = (CGFloat(index) / CGFloat(rays)) * .pi * 2 - .pi / 2
            let length = radius * (index.isMultiple(of: 2) ? 1.0 : 0.74)
            let halfWidth = radius * 0.085
            let inner = radius * innerRatio

            let tip = point(center, angle, length)
            let base = point(center, angle, inner)
            let normal = angle + .pi / 2
            let left = point(base, normal, halfWidth)
            let right = point(base, normal, -halfWidth)
            let shoulder = point(center, angle, inner + (length - inner) * 0.42)

            path.move(to: left)
            path.addQuadCurve(to: tip, control: point(shoulder, normal, halfWidth * 1.15))
            path.addQuadCurve(to: right, control: point(shoulder, normal, -halfWidth * 1.15))
            path.closeSubpath()
        }
        path.addEllipse(in: CGRect(
            x: center.x - radius * innerRatio * 1.3,
            y: center.y - radius * innerRatio * 1.3,
            width: radius * innerRatio * 2.6,
            height: radius * innerRatio * 2.6
        ))
        return path
    }

    private func point(_ origin: CGPoint, _ angle: CGFloat, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
    }
}

/// The animated spark. When `isActive`, it slowly turns and breathes,
/// signalling that Claude is waiting on you. `isPaused` holds an active spark
/// still, in its glowing pose, while it can't be seen.
struct ClaudeSpark: View {
    var size: CGFloat = 18
    var isActive = true
    var isPaused = false
    var color: Color = Theme.Palette.clay

    var body: some View {
        // 30 fps is plenty for a slow turn (15°/s) and breath, at half the redraws of 60.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive || isPaused)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breathe = isActive ? 1 + 0.06 * sin(time * 2.4) : 1
            SparkShape()
                .fill(color)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(isActive ? time.truncatingRemainder(dividingBy: 24) * 15 : 0))
                .scaleEffect(breathe)
                .shadow(color: color.opacity(isActive ? 0.55 : 0), radius: size * 0.35)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 24) {
        ClaudeSpark(size: 18)
        ClaudeSpark(size: 36, isActive: false)
    }
    .padding(40)
    .background(.black)
}
