import AppKit
import SwiftUI

/// The Now Playing card at the top of the hover panel: artwork, a scrolling
/// title, a scrubbable playhead and transport controls, all lit by a color
/// picked from the artwork.
struct NowPlayingCardView: View {
    let monitor: NowPlayingMonitor

    static let cornerRadius: CGFloat = 18

    private var accent: Color { monitor.accent.map { Color(nsColor: $0) } ?? Theme.Palette.clay }

    /// Brings the player forward; `nil` when its app is unknown.
    private var openPlayer: (() -> Void)? {
        guard monitor.track?.appBundleID != nil else { return nil }
        return { [monitor] in monitor.openPlayer() }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if let track = monitor.track {
                player(track)
                    .transition(.opacity)
            } else {
                emptyState
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background(NowPlayingBackdrop(wash: monitor.backdrop, accent: accent))
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.6
            )
        )
        .animation(.easeInOut(duration: 0.6), value: monitor.accent)
        .animation(Theme.Motion.content, value: monitor.track == nil)
    }

    // MARK: Player

    private func player(_ track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(track)

            HStack(alignment: .center, spacing: 14) {
                NowPlayingArtwork(
                    image: monitor.artwork,
                    accent: accent,
                    isPlaying: track.isPlaying,
                    size: 68,
                    action: openPlayer
                )
                VStack(alignment: .leading, spacing: 4) {
                    MarqueeText(text: track.title, font: .system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let subtitle = track.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PlayheadView(track: track, accent: accent, onSeek: monitor.seek)

            TransportRow(track: track, accent: accent, monitor: monitor)
        }
    }

    private func header(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 7) {
            EqualizerBars(isPlaying: track.isPlaying, color: accent, barCount: 3, barWidth: 2, spacing: 1.5, height: 10)
            Text(track.isPlaying ? "Now Playing" : "Paused")
                .font(Theme.Typeface.micro)
                .foregroundStyle(Theme.Palette.textTertiary)
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            if let name = track.appName {
                SourceChip(name: name, icon: monitor.appIcon, action: openPlayer)
            }
        }
        .animation(Theme.Motion.content, value: track.isPlaying)
    }

    // MARK: Nothing playing

    private var emptyState: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Theme.Palette.surfaceRaised, Theme.Palette.surface], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: monitor.setupError == nil ? "music.note" : "exclamationmark.triangle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.setupError == nil ? "Nothing playing" : "Now Playing is unavailable")
                    .font(Theme.Typeface.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(monitor.setupError ?? "Play something in Music, Spotify, Podcasts or a browser tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The artwork's colors washed behind the card, like Music's full-screen player.
private struct NowPlayingBackdrop: View {
    /// Pre-blurred artwork (see `ArtworkPalette.backdrop`).
    let wash: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            Color.white.opacity(0.035)
            if let wash {
                Image(nsImage: wash)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.3)
                    .saturation(1.4)
                    .opacity(0.42)
                    .clipped()
                    .transition(.opacity)
            }
            RadialGradient(colors: [accent.opacity(0.3), .clear], center: .topLeading, startRadius: 0, endRadius: 280)
            LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.5), value: wash)
        .allowsHitTesting(false)
    }
}

/// The player app's icon and name; clicking brings it forward.
private struct SourceChip: View {
    let name: String
    let icon: NSImage?
    let action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                }
                Text(name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                if action != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .opacity(isHovered ? 1 : 0.6)
                }
            }
            .foregroundStyle(isHovered ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            .padding(.leading, icon == nil ? 8 : 4)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(isHovered ? 0.12 : 0.07)))
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.95))
        .disabled(action == nil)
        .onHover { isHovered = $0 && action != nil }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Open \(name)")
    }
}

/// The scrubber with elapsed and remaining time. Drag (or click) to seek.
private struct PlayheadView: View {
    let track: NowPlayingTrack
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    /// Where the knob is while being dragged; seeking happens on release.
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !track.isPlaying || dragFraction != nil)) { context in
            let position = track.position(at: context.date)
            let fraction = dragFraction ?? track.progress(at: context.date) ?? 0
            VStack(spacing: 5) {
                MediaSlider(
                    value: track.duration == nil ? 1 : fraction,
                    tint: track.duration == nil ? Theme.Palette.textTertiary : accent,
                    isInteractive: track.canSeek,
                    onChanged: { dragFraction = $0 },
                    onEnded: { fraction in
                        if let duration = track.duration { onSeek(fraction * duration) }
                        dragFraction = nil
                    }
                )
                times(position: position, fraction: fraction)
            }
        }
    }

    @ViewBuilder
    private func times(position: TimeInterval?, fraction: Double) -> some View {
        HStack {
            if let duration = track.duration {
                let shown = dragFraction.map { $0 * duration } ?? position ?? 0
                Text(NowPlayingTrack.clock(shown))
                Spacer()
                Text("-" + NowPlayingTrack.clock(duration - shown))
            } else {
                if let position { Text(NowPlayingTrack.clock(position)) }
                Spacer()
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Theme.Palette.danger.opacity(0.9))
            }
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(dragFraction == nil ? Theme.Palette.textTertiary : Theme.Palette.textSecondary)
    }
}

/// Shuffle, ±15 s, previous, play / pause, next, repeat, spread across the card:
/// only what the player supports (a browser tab can't shuffle or repeat).
private struct TransportRow: View {
    let track: NowPlayingTrack
    let accent: Color
    let monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 0) {
            if track.canShuffle {
                TransportButton(
                    systemName: "shuffle", help: track.isShuffling ? "Shuffle off" : "Shuffle",
                    size: 12.5, isActive: track.isShuffling, tint: accent, action: monitor.toggleShuffle
                )
                gap
            }
            if track.canSeek {
                TransportButton(systemName: "gobackward.15", help: "Back 15 seconds", size: 14) { monitor.skip(by: -15) }
                gap
            }
            TransportButton(systemName: "backward.fill", help: "Previous", size: 16, action: monitor.previousTrack)
                .disabled(!track.canGoPrevious)
            gap
            PlayPauseButton(isPlaying: track.isPlaying, accent: accent, action: monitor.togglePlayPause)
            gap
            TransportButton(systemName: "forward.fill", help: "Next", size: 16, action: monitor.nextTrack)
                .disabled(!track.canGoNext)
            if track.canSeek {
                gap
                TransportButton(systemName: "goforward.15", help: "Forward 15 seconds", size: 14) { monitor.skip(by: 15) }
            }
            if track.canRepeat {
                gap
                TransportButton(
                    systemName: "repeat", help: repeatHelp, size: 12.5,
                    isActive: track.repeating != .off, tint: accent,
                    badge: track.repeating == .one ? "1" : nil, action: monitor.cycleRepeat
                )
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    /// Stretches to fill the card with the full row, but keeps a short row
    /// (no shuffle or repeat) together in the middle.
    private var gap: some View {
        Spacer(minLength: 2).frame(maxWidth: 30)
    }

    private var repeatHelp: String {
        switch track.repeating {
        case .off: return "Repeat"
        case .all: return "Repeat one"
        case .one: return "Repeat off"
        }
    }
}
