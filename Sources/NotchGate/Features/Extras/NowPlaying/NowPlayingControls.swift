import AppKit
import SwiftUI

/// Album art (or a tinted placeholder) that breathes with playback: full size
/// with a colored glow while playing, settled back a little while paused.
struct NowPlayingArtwork: View {
    let image: NSImage?
    let accent: Color
    let isPlaying: Bool
    var size: CGFloat = 72
    var cornerRadius: CGFloat = 12
    /// Clicking the artwork brings the player forward.
    var action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            if action != nil, isHovered {
                Color.black.opacity(0.38)
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: accent.opacity(isPlaying ? 0.55 : 0.2), radius: isPlaying ? size * 0.22 : size * 0.1, y: size * 0.08)
        .scaleEffect(isPlaying ? 1 : 0.9)
        .contentShape(shape)
        .onTapGesture { action?() }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: isPlaying)
        .animation(.easeInOut(duration: 0.35), value: image)
        .help(action == nil ? "" : "Open the player")
        .accessibilityHidden(true)
    }
}

/// A little live equalizer: bars dance while playing and settle into dots when paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    var color: Color
    var barCount = 4
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var height: CGFloat = 14

    private static let speeds: [Double] = [6.1, 8.3, 5.2, 7.4, 6.7]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.9, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                        .frame(width: barWidth, height: barHeight(index, time: time))
                }
            }
            .frame(height: height)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isPlaying)
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return barWidth }
        let speed = Self.speeds[index % Self.speeds.count], phase = Self.phases[index % Self.phases.count]
        // Two out-of-step waves per bar read as music rather than a metronome.
        let wave = (sin(time * speed + phase) + sin(time * speed * 0.47 + phase * 2)) / 4 + 0.5
        return max(barWidth, height * (0.22 + 0.78 * wave))
    }
}

/// A title that scrolls slowly when it doesn't fit, pausing at the start of each pass.
struct MarqueeText: View {
    let text: String
    var font: Font
    /// Points per second.
    var speed: CGFloat = 30
    var pause: Double = 2.4
    var gap: CGFloat = 40

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private var overflows: Bool { textWidth > boxWidth + 0.5 && boxWidth > 0 }

    var body: some View {
        // Sizes the box to one line; the visible copy scrolls inside it.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { boxWidth = $0 })
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !overflows)) { context in
                    let offset = offset(at: context.date)
                    HStack(spacing: gap) {
                        label.onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { textWidth = $0 })
                        if overflows { label }
                    }
                    .offset(x: -offset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask(fade(scrolled: offset > 0))
                }
            }
            .clipped()
            .onChange(of: text) { _, _ in start = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        guard overflows else { return 0 }
        let distance = textWidth + gap
        let travel = Double(distance / speed)
        let time = date.timeIntervalSince(start).truncatingRemainder(dividingBy: pause + travel)
        return time < pause ? 0 : CGFloat(time - pause) * speed
    }

    private func fade(scrolled: Bool) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: scrolled ? .clear : .black, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: overflows ? 0.9 : 1),
                .init(color: overflows ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

/// A thin capsule slider that thickens and shows its knob under the cursor,
/// like the scrubber in Music.
struct MediaSlider: View {
    /// 0…1.
    let value: Double
    var tint: Color
    var isInteractive = true
    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void = { _ in }

    @State private var isHovered = false
    @State private var isDragging = false

    private var isActive: Bool { isInteractive && (isHovered || isDragging) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(value, 0), 1)
            let thickness: CGFloat = isActive ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: thickness)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(thickness, width * fraction), height: thickness)
                    .shadow(color: tint.opacity(isActive ? 0.55 : 0.25), radius: isActive ? 6 : 3)
                if isInteractive {
                    Circle()
                        .fill(Theme.Palette.ivory)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .scaleEffect(isActive ? 1 : 0.2)
                        .opacity(isActive ? 1 : 0)
                        .offset(x: min(max(0, width * fraction - 6), width - 12))
                }
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChanged(Self.fraction(drag.location.x, width: width))
                    }
                    .onEnded { drag in
                        isDragging = false
                        onEnded(Self.fraction(drag.location.x, width: width))
                    },
                including: isInteractive ? .all : .none
            )
        }
        .frame(height: 14)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isActive)
    }

    private static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }
}

/// A round, borderless transport button: lights up on hover, sinks when pressed,
/// and wears the accent (with a dot) while its mode is on.
struct TransportButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 14
    var isActive = false
    var tint: Color = Theme.Palette.clay
    /// A tiny superscript on the glyph, like the "1" of repeat one.
    var badge: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .symbolEffect(.bounce.down, value: taps)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
                            .fixedSize()
                            .offset(x: size * 0.3, y: -size * 0.4)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .foregroundStyle(isActive ? tint : (isHovered ? Theme.Palette.textPrimary : Theme.Palette.textSecondary))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.1 : 0)))
                .overlay(alignment: .bottom) {
                    if isActive {
                        Circle().fill(tint).frame(width: 3.5, height: 3.5).offset(y: -2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.28)
        .onHover { isHovered = $0 && isEnabled }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: badge)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The big ivory play / pause button with a glow in the artwork's color.
struct PlayPauseButton: View {
    let isPlaying: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.Palette.ivory, Theme.Palette.ivory.opacity(0.86)], startPoint: .top, endPoint: .bottom))
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    // The play triangle's visual center sits right of its box.
                    .offset(x: isPlaying ? 0 : 1.5)
            }
            .frame(width: 44, height: 44)
            .shadow(color: accent.opacity(isHovered ? 0.7 : 0.45), radius: isHovered ? 16 : 10, y: 3)
            .scaleEffect(isHovered ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Shrinks a button a touch while it's held down.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
