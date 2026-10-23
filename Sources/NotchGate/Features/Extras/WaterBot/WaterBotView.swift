import SwiftUI

/// The water bot (or Spidey, Batman or the dev; see `WaterCharacter`) hanging from the notch with
/// its speech bubble. Hover it to reveal Drank it / Snooze; click it and it
/// giggles. It sips, celebrates and climbs back up when you drink.
struct WaterBotView: View {
    let water: WaterReminder
    let isHovered: Bool
    /// Reports the bot's clickable area (window coordinates) for hit-testing.
    let onHitAreaChange: (CGRect) -> Void

    /// Stage size, centered under the notch. The rope sits left of center so it
    /// leaves from the notch itself while the bubble floats out to the right.
    static let size = CGSize(width: 440, height: 300)
    private static let figureOrigin = CGPoint(x: 104, y: 0)
    private static let bubbleOrigin = CGPoint(x: 246, y: 36)
    private static let trayTop: CGFloat = 212

    @State private var appearedAt = Date()
    @State private var pokedAt: Date?
    @State private var pokes = 0
    @State private var spin = 0.0
    @State private var parts: [Part: CGRect] = [:]

    private enum Part { case figure, bubble, tray }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            stage(at: context.date)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .onChange(of: parts) { _, parts in
            onHitAreaChange(parts.values.reduce(CGRect.null) { $0.union($1) })
        }
        .onDisappear { onHitAreaChange(.zero) }
    }

    private func stage(at date: Date) -> some View {
        let time = date.timeIntervalSince(appearedAt)
        let mood = mood(at: date)
        let sipTime = water.drankAt.map { date.timeIntervalSince($0) }

        return ZStack(alignment: .topLeading) {
            figure(mood: mood, time: time, sipTime: sipTime)
                .rotation3DEffect(
                    .degrees(spin), axis: (x: 0, y: 1, z: 0),
                    anchor: UnitPoint(x: ropeAnchor.x / WaterBotFigure.size.width, y: 0.5)
                )
                .contentShape(Rectangle().offset(y: 40).size(width: WaterBotFigure.size.width, height: WaterBotFigure.size.height - 40))
                .onTapGesture(perform: poke)
                .help("Poke me")
                .measure(.figure, into: $parts)
                .padding(.leading, Self.figureOrigin.x)
                .padding(.top, Self.figureOrigin.y)

            Sparkles(time: time, sipTime: sipTime, splash: splash)
                .allowsHitTesting(false)

            WaterBotBubble(
                title: title(for: mood),
                detail: detail(for: mood),
                glasses: water.glassesToday,
                goal: water.settings.waterDailyGoal
            )
            .scaleEffect(Self.pop(time - 0.45), anchor: .bottomLeading)
            .opacity(min(1, max(0, (time - 0.45) * 6)))
            .onTapGesture(perform: poke)
            .measure(.bubble, into: $parts)
            .padding(.leading, Self.bubbleOrigin.x)
            .padding(.top, Self.bubbleOrigin.y)

            if isHovered && water.state == .asking {
                actions
                    .measure(.tray, into: $parts)
                    .frame(width: Self.size.width - 120)
                    .padding(.leading, 120)
                    .padding(.top, Self.trayTop)
                    .transition(.opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHovered && water.state == .asking)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: title(for: mood))
    }

    @ViewBuilder
    private func figure(mood: WaterBotMood, time: TimeInterval, sipTime: TimeInterval?) -> some View {
        switch water.character {
        case .robot:
            WaterBotFigure(mood: mood, time: time, sip: Self.sip(at: sipTime), waterLevel: Self.waterLevel(at: sipTime))
        case .spidey:
            SpideyFigure(mood: mood, time: time, sip: Self.sip(at: sipTime), waterLevel: Self.waterLevel(at: sipTime))
        case .batman:
            BatFigure(mood: mood, time: time, sip: Self.sip(at: sipTime), waterLevel: Self.waterLevel(at: sipTime))
        case .developer:
            DevFigure(mood: mood, time: time, sip: Self.sip(at: sipTime), waterLevel: Self.waterLevel(at: sipTime))
        }
    }

    /// Where the rope (web, grapnel line, headphone cable) leaves the notch; the figure twirls around it.
    private var ropeAnchor: CGPoint {
        switch water.character {
        case .robot: return WaterBotFigure.ropeAnchor
        case .spidey: return SpideyFigure.ropeAnchor
        case .batman: return BatFigure.ropeAnchor
        case .developer: return DevFigure.ropeAnchor
        }
    }

    /// Where the drink splash bursts from: the robot's visor or the hero's mouth, in stage coordinates.
    private var splash: CGPoint {
        switch water.character {
        case .robot: return WaterBotFigure.mouth + Self.figureOrigin
        case .spidey: return SpideyFigure.mouth + Self.figureOrigin
        case .batman: return BatFigure.mouth + Self.figureOrigin
        case .developer: return DevFigure.mouth + Self.figureOrigin
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: water.drink) {
                Label("Drank it", systemImage: "drop.fill")
            }
            .buttonStyle(.island(.primary))
            .help("Log a glass of water")

            Button(action: water.snooze) {
                Label("Snooze \(water.settings.waterSnoozeMinutes)m", systemImage: "moon.zzz.fill")
            }
            .buttonStyle(.island(.secondary))
            .help("Remind me in \(WaterReminder.format(minutes: water.settings.waterSnoozeMinutes))")

            IconButton(systemName: "xmark", help: "Skip this one", action: water.skip)
        }
        .padding(6)
        .background(Capsule().fill(Theme.Palette.island))
        .overlay(Capsule().strokeBorder(Theme.Palette.clay.opacity(0.35), lineWidth: 0.8))
        .shadow(color: Theme.Palette.clay.opacity(0.3), radius: 12)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .fixedSize()
    }

    // MARK: Mood & words

    private func mood(at date: Date) -> WaterBotMood {
        WaterBotMood.current(
            state: water.state,
            waited: water.askedAt.map { date.timeIntervalSince($0) } ?? 0,
            isHovered: isHovered,
            isUserAway: water.isUserAway,
            isTickled: pokedAt.map { date.timeIntervalSince($0) < 1.4 } ?? false
        )
    }

    private func title(for mood: WaterBotMood) -> String {
        switch mood {
        case .delighted where water.goalReached && water.glassesToday == water.settings.waterDailyGoal:
            return "Goal reached!"
        case .sleepy where water.state == .snoozing:
            return "Okay… nap time"
        case .tickled:
            return mood.line(variant: pokes, character: water.character)
        default:
            return mood.line(variant: water.reminderCount - 1, character: water.character)
        }
    }

    /// Second line of the bubble; nil shows today's glasses as droplets.
    private func detail(for mood: WaterBotMood) -> String? {
        if water.isPreview, water.state == .drinking || water.state == .snoozing {
            return "Just a preview"
        }
        switch water.state {
        case .snoozing:
            return "Back in \(WaterReminder.format(minutes: water.settings.waterSnoozeMinutes))"
        case .drinking:
            let goal = water.settings.waterDailyGoal
            return water.glassesToday >= goal ? "\(water.glassesToday) glasses today" : "\(water.glassesToday) of \(goal) today"
        case .asking where mood == .sleepy:
            return "Drink when you're back"
        default:
            return nil
        }
    }

    // MARK: Interaction

    private func poke() {
        guard water.state == .asking else { return }
        pokes += 1
        pokedAt = Date()
        if water.settings.playSound { SoundPlayer.play(.resolve, volume: 0.15) }
        // Every fifth poke it does a little twirl on its rope (or web).
        if pokes.isMultiple(of: 5) {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { spin += 360 }
        }
    }

    // MARK: Choreography (seconds since the glass was logged)

    /// Raises the bottle, holds it while drinking, lowers it again.
    private static func sip(at elapsed: TimeInterval?) -> CGFloat {
        guard let elapsed else { return 0 }
        if elapsed < 0.45 { return CGFloat(elapsed / 0.45) }
        if elapsed < 1.5 { return 1 }
        return CGFloat(max(0, 1 - (elapsed - 1.5) / 0.4))
    }

    private static func waterLevel(at elapsed: TimeInterval?) -> CGFloat {
        guard let elapsed else { return 0.8 }
        return 0.8 - 0.55 * CGFloat(min(1, max(0, (elapsed - 0.4) / 1.0)))
    }

    /// Overshooting pop-in (easeOutBack) for the bubble.
    private static func pop(_ elapsed: TimeInterval) -> CGFloat {
        let progress = min(1, max(0, elapsed / 0.4))
        let overshoot = 1.9
        let shifted = progress - 1
        return CGFloat(max(0.2, 1 + (overshoot + 1) * pow(shifted, 3) + overshoot * pow(shifted, 2)))
    }
}

/// Drops and sparkles floating around the bubble, plus a splash when you drink.
private struct Sparkles: View {
    let time: TimeInterval
    let sipTime: TimeInterval?
    /// Burst origin: where the bottle meets the face, in stage coordinates.
    let splash: CGPoint

    var body: some View {
        Canvas { context, _ in
            let fade = min(1, max(0, (time - 0.6) * 2))
            context.opacity = fade
            for (index, point) in [CGPoint(x: 240, y: 30), CGPoint(x: 432, y: 60), CGPoint(x: 406, y: 124)].enumerated() {
                let bob = CGPoint(x: point.x, y: point.y + 3 * sin(time * 2 + Double(index) * 2))
                if index == 1 {
                    context.fill(DropShape().path(in: CGRect(x: bob.x - 4.5, y: bob.y - 6, width: 9, height: 12)),
                                 with: .color(Theme.Palette.clay))
                } else {
                    let scale = 1 + 0.2 * sin(time * 3 + Double(index))
                    context.fill(SparkShape(rays: 4, innerRatio: 0.2).path(in: CGRect(center: bob, radius: 6 * scale)),
                                 with: .color(Theme.Palette.clayGlow))
                }
            }

            guard let sipTime else { return }
            let burst = sipTime - 1.2
            guard burst > 0, burst < 1.4 else { return }
            context.opacity = 1 - burst / 1.4
            for index in 0..<16 {
                let angle = Double(index) / 16 * 2 * .pi + 0.3
                let speed = 70 + Double((index * 37) % 50)
                let point = CGPoint(
                    x: splash.x + cos(angle) * speed * burst,
                    y: splash.y + sin(angle) * speed * burst + 60 * burst * burst
                )
                if index.isMultiple(of: 3) {
                    context.fill(SparkShape(rays: 4, innerRatio: 0.2).path(in: CGRect(center: point, radius: 5)),
                                 with: .color(Theme.Palette.clayGlow))
                } else {
                    let color = index.isMultiple(of: 2) ? Bottle.water : Theme.Palette.clay
                    context.fill(DropShape().path(in: CGRect(x: point.x - 3.5, y: point.y - 5, width: 7, height: 10)),
                                 with: .color(color))
                }
            }
        }
        .frame(width: WaterBotView.size.width, height: WaterBotView.size.height)
    }
}

private extension View {
    /// Records this view's window-space frame under `part`.
    func measure<Part: Hashable>(_ part: Part, into frames: Binding<[Part: CGRect]>) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frames.wrappedValue[part] = $0 })
            .onDisappear { frames.wrappedValue[part] = nil }
    }
}
