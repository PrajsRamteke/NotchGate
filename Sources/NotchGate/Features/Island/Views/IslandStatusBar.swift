import SwiftUI

/// The strip that sits level with the hardware notch. Content lives in the
/// two "wings" either side of the camera housing; the middle stays empty.
struct IslandStatusBar: View {
    let model: IslandViewModel

    private var presentation: IslandPresentation { model.presentation }

    /// The closed notch is showing what's playing rather than Claude.
    private var showsMusic: Bool { presentation == .peek && model.showsNowPlayingPeek }

    private var musicAccent: Color { model.nowPlaying.accent.map { Color(nsColor: $0) } ?? Theme.Palette.clay }

    var body: some View {
        HStack(spacing: 0) {
            leadingWing
            Spacer(minLength: model.notch.notchSize.width)
            trailingWing
        }
        .padding(.horizontal, showsMusic ? 6 : 12)
        .opacity(presentation == .hidden ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if presentation == .peek || model.isRequestMinimized { model.expand() } }
    }

    private var leadingWing: some View {
        HStack(spacing: 7) {
            if showsMusic {
                NowPlayingArtwork(image: model.nowPlaying.artwork, accent: musicAccent, isPlaying: true, size: 20, cornerRadius: 5)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                ClaudeSpark(size: 14, isActive: model.store.hasPending || model.activity.workingCount > 0, color: sparkColor)
            }
            if presentation == .expanded, let title = leadingTitle {
                Text(title)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
    }

    private var leadingTitle: String? {
        if model.isShowingActivity { return "Claude" }
        return model.store.current?.session.projectName
    }

    @ViewBuilder
    private var trailingWing: some View {
        if model.store.hasPending {
            PendingBadge(count: model.store.pendingCount)
        } else if let notice = model.store.notice {
            Image(systemName: notice.tone.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(notice.tone.color)
                .symbolEffect(.bounce, value: notice.id)
        } else if showsMusic {
            EqualizerBars(isPlaying: true, color: musicAccent, height: 12)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    private var sparkColor: Color {
        model.store.notice?.tone == .done && !model.store.hasPending ? Theme.Palette.success : Theme.Palette.clay
    }
}

private struct PendingBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.Palette.ivory)
            .monospacedDigit()
            .contentTransition(.numericText())
            .frame(minWidth: 18, minHeight: 18)
            .background(Circle().fill(Theme.Palette.clay))
            .animation(.spring(response: 0.3), value: count)
            .accessibilityLabel("\(count) pending")
    }
}

extension Notice.Tone {
    var symbol: String {
        switch self {
        case .attention: return "bell.fill"
        case .done: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .attention: return Theme.Palette.clay
        case .done: return Theme.Palette.success
        case .info: return Theme.Palette.textSecondary
        }
    }
}
