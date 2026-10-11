import SwiftUI

/// A thin ring that drains as `deadline` approaches.
struct CountdownRing: View {
    let start: Date
    let deadline: Date
    var size: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let total = max(deadline.timeIntervalSince(start), 1)
            let remaining = max(deadline.timeIntervalSince(context.date), 0)
            ZStack {
                Circle().stroke(Theme.Palette.hairline, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: remaining / total)
                    .stroke(Theme.Palette.clay, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            .help("\(Int(remaining.rounded(.up)))s until Claude continues in the terminal")
        }
        .accessibilityHidden(true)
    }
}
