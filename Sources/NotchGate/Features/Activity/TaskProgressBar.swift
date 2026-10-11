import SwiftUI

/// Claude's to-do list as a slim progress bar: "3 of 7 · Writing tests".
struct TaskProgressBar: View {
    let progress: TaskProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.hairline)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.Palette.clayDeep, Theme.Palette.clay],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(4, proxy.size.width * progress.fraction))
                        .shadow(color: Theme.Palette.clay.opacity(0.45), radius: 4)
                }
            }
            .frame(height: 4)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress.fraction)

            HStack(spacing: 4) {
                Text("\(progress.completed) of \(progress.total)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let current = progress.current {
                    Text("·").foregroundStyle(Theme.Palette.textTertiary)
                    Text(current)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .font(Theme.Typeface.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(progress.completed) of \(progress.total) tasks done")
    }
}
