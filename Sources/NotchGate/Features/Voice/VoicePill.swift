import SwiftUI

/// The dark capsule Notch Voice shows at the bottom of the screen: a live waveform
/// while you talk, then what happened to your words.
struct VoicePill: View {
    /// The longest the live words run before the oldest scroll off the left.
    static let liveTextWidth: CGFloat = 360

    let phase: VoiceDictation.Phase
    let levels: [Float]
    /// The words heard so far (AI clean-up off), shown while listening.
    var liveText = ""

    var body: some View {
        HStack(spacing: 9) {
            content
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Theme.Palette.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Palette.island.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.07), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        )
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.13), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.3), value: kind)
        .animation(.easeOut(duration: 0.18), value: liveText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .listening(let since):
            RecordingDot()
            if liveText.isEmpty {
                VoiceWaveform(levels: levels)
            } else {
                CappedWidth(maxWidth: Self.liveTextWidth) {
                    Text(liveText)
                        .font(.system(size: 12.5, weight: .medium))
                        .truncationMode(.head)
                }
                .transition(.opacity)
                VoiceWaveform(levels: Array(levels.suffix(8)))
            }
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(minWidth: 30, alignment: .trailing)
        case .transcribing:
            ThinkingWave()
            Text("Transcribing")
        case .cleaningUp(let service):
            if service == .claude {
                ClaudeSpark(size: 15, isActive: true)
            } else {
                symbol("sparkles", color: Theme.Palette.clayGlow)
                    .symbolEffect(.pulse)
            }
            Text(service.workingTitle)
        case .inserted(let words):
            symbol("checkmark.circle.fill", color: Theme.Palette.success)
            Text("Inserted")
            Text(words == 1 ? "1 word" : "\(words) words")
                .foregroundStyle(Theme.Palette.textTertiary)
        case .copied(let reason):
            symbol("doc.on.clipboard.fill", color: Theme.Palette.clay)
            Text(copiedText(reason))
        case .nothingHeard:
            symbol("waveform.slash", color: Theme.Palette.textSecondary)
            Text("Didn't catch that")
                .foregroundStyle(Theme.Palette.textSecondary)
        case .failed(let error):
            symbol("exclamationmark.triangle.fill", color: Theme.Palette.warning)
            Text(error.title)
        }
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
            .transition(.scale.combined(with: .opacity))
    }

    private func copiedText(_ reason: TextInserter.CopyReason) -> String {
        switch reason {
        case .secureInput: return "Password field · copied, press ⌘V"
        case .accessibilityOff: return "Allow Accessibility to type · copied"
        }
    }

    /// Changes only when the pill's content changes, not on every waveform tick.
    private var kind: Int {
        switch phase {
        case .idle: return 0
        case .listening: return 1
        case .transcribing: return 2
        case .cleaningUp: return 3
        case .inserted: return 4
        case .copied: return 5
        case .nothingHeard: return 6
        case .failed: return 7
        }
    }
}

/// Its content at its natural width, up to `maxWidth`, pinned to the trailing edge (a
/// `frame(maxWidth:)` would always grow to the maximum).
private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

/// The clay "on air" dot, breathing while the microphone is open.
private struct RecordingDot: View {
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.clay.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(breathing ? 1.25 : 0.6)
                .opacity(breathing ? 0 : 0.9)
            Circle()
                .fill(Theme.Palette.clay)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { breathing = true }
        }
        .accessibilityLabel("Listening")
    }
}

/// Bars that follow your voice, newest on the right.
struct VoiceWaveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(Theme.Palette.ivory.opacity(0.3 + 0.7 * Double(index + 1) / Double(levels.count)))
                    .frame(width: 3, height: 3 + CGFloat(level) * 19)
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.12), value: levels)
        .accessibilityHidden(true)
    }
}

/// A gentle travelling wave while the words are worked out.
private struct ThinkingWave: View {
    private let bars = 9

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { index in
                    let wave = (sin(time * 7 - Double(index) * 0.7) + 1) / 2
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.clayGlow.opacity(0.45 + 0.55 * wave))
                        .frame(width: 3, height: 4 + 10 * wave)
                }
            }
            .frame(height: 22)
        }
        .accessibilityHidden(true)
    }
}
