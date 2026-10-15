import SwiftUI

/// The water bot, drawn in code: a little ivory-and-clay robot clipped by the
/// ring on its antenna to a rope from the notch, waving with one hand and
/// holding the bottle in the other. Everything is a function of `mood` and
/// `time`, so wrapping it in a `TimelineView` animates it.
struct WaterBotFigure: View {
    var mood: WaterBotMood
    /// Seconds since the bot appeared; drives the idle motion.
    var time: TimeInterval
    /// 0 = bottle at its side, 1 = tipped against the visor.
    var sip: CGFloat = 0
    /// How full the bottle is, 0…1.
    var waterLevel: CGFloat = 0.8

    static let size = CGSize(width: 160, height: 204)
    /// Where the rope leaves the top edge; the bot swings around it.
    static let ropeAnchor = CGPoint(x: 72, y: 0)
    /// Where the bottle meets the visor, for the splash when you drink.
    static let mouth = CGPoint(x: 78, y: 99)

    var body: some View {
        let motion = Motion(mood: mood, time: time)
        Canvas { context, _ in
            draw(in: context, motion: motion)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(0.4), radius: 5, y: 4)
        .rotationEffect(
            .degrees(motion.swing),
            anchor: UnitPoint(x: Self.ropeAnchor.x / Self.size.width, y: 0)
        )
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    /// The ring on top of the antenna; the bot hangs (and tilts) from it.
    private static let ring = CGPoint(x: 72, y: 40)
    private static let leftShoulder = CGPoint(x: 55, y: 131)
    private static let rightShoulder = CGPoint(x: 89, y: 131)

    private func draw(in context: GraphicsContext, motion: Motion) {
        let ring = Self.ring + CGPoint(x: 0, y: motion.lift)
        drawRope(in: context, to: ring + CGPoint(x: 0, y: -19))

        var bot = context
        bot.translateBy(x: ring.x, y: ring.y)
        bot.rotate(by: .degrees(motion.tilt))
        bot.translateBy(x: -Self.ring.x, y: -Self.ring.y)
        let ink = Palette.inkStyle.turned(by: motion.tilt)

        drawCarabiner(in: bot, ink: ink)
        drawLegs(in: bot, ink: ink, motion: motion)
        drawTorso(in: bot, ink: ink)
        drawHead(in: bot, ink: ink)

        let (bottleCenter, bottleAngle) = bottlePose(wiggle: motion.wiggle)
        let grip = bottleCenter + Bottle.offset(CGPoint(x: -6, y: 7), angle: bottleAngle)
        drawArm(in: bot, ink: ink, from: Self.rightShoulder, to: grip, bend: -0.22, handAngle: bottleAngle - 10, thumb: -1)
        Palette.bottle.draw(in: bot, center: bottleCenter, angle: bottleAngle, level: waterLevel, time: time, ink: ink, capped: sip < 0.3)
        drawHand(in: bot, ink: ink, at: grip, angle: bottleAngle - 10, thumb: -1)

        let free = freeHand(motion: motion)
        drawArm(in: bot, ink: ink, from: Self.leftShoulder, to: free.point, bend: free.bend, handAngle: free.angle, thumb: 1)
        drawHand(in: bot, ink: ink, at: free.point, angle: free.angle, thumb: 1)

        drawMoodExtras(in: bot)
    }

    private func drawRope(in context: GraphicsContext, to end: CGPoint) {
        var rope = Path()
        rope.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        rope.addLine(to: end)
        context.stroke(rope, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
        context.stroke(rope, with: .color(Palette.clay.base), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        // Twisted strands: short slanted dashes in a deeper clay.
        context.stroke(rope, with: .color(Palette.clay.shade), style: StrokeStyle(lineWidth: 3.8, dash: [1.6, 2.4]))
        var shine = Path()
        shine.move(to: CGPoint(x: Self.ropeAnchor.x - 0.9, y: -6))
        shine.addLine(to: end + CGPoint(x: -0.9, y: 0))
        context.stroke(shine, with: .color(Palette.clay.light.opacity(0.8)), style: StrokeStyle(lineWidth: 0.8, dash: [1.6, 2.4]))
    }

    /// The clip on the end of the rope, hooked through the antenna ring.
    private func drawCarabiner(in context: GraphicsContext, ink: Ink) {
        let clip = RoundedRectangle(cornerRadius: 4.6, style: .continuous).path(in: CGRect(x: 67.4, y: 19, width: 9.2, height: 20))
        context.stroke(clip, with: .color(Palette.ink), lineWidth: 4.4)
        context.stroke(clip, with: .color(Palette.steel), lineWidth: 2)
        var gate = Path()
        gate.move(to: CGPoint(x: 76.6, y: 24))
        gate.addLine(to: CGPoint(x: 74.4, y: 34))
        context.stroke(gate, with: .color(Palette.ink), lineWidth: 1)

        // Ring and antenna stalk, drawn over the clip's lower bar so they interlock.
        var stalk = Path()
        stalk.move(to: Self.ring + CGPoint(x: 0, y: 4))
        stalk.addLine(to: Self.ring + CGPoint(x: 0, y: 13))
        context.stroke(stalk, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5.4, lineCap: .round))
        context.stroke(stalk, with: .color(Palette.joint.light), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let ring = Circle().path(in: CGRect(center: Self.ring, radius: 4.4))
        context.stroke(ring, with: .color(Palette.ink), lineWidth: 4.8)
        context.stroke(ring, with: .color(Palette.clay.base), lineWidth: 2.2)
        var glint = Path()
        glint.addArc(center: Self.ring, radius: 4.4, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        context.stroke(glint, with: .color(Palette.clay.light), style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private func drawLegs(in context: GraphicsContext, ink: Ink, motion: Motion) {
        for (hip, angle) in [(CGPoint(x: 64, y: 154), motion.legLeft), (CGPoint(x: 80, y: 154), motion.legRight)] {
            let foot = hip + CGPoint(x: 0, y: 19).rotated(by: angle)
            ink.paint(Sketch.limb(hip, (hip + foot) * 0.5, foot, 4.2, 3.6), Palette.joint, in: context)

            var boot = context
            boot.translateBy(x: foot.x, y: foot.y)
            boot.rotate(by: .degrees(angle))
            let bootInk = ink.turned(by: angle)
            let shoe = Path(roundedRect: CGRect(x: -8.5, y: -4, width: 17, height: 11), cornerRadius: 5.5, style: .continuous)
            bootInk.paint(shoe, Palette.shell, in: boot)
            var sole = boot
            sole.clip(to: shoe)
            sole.fill(Path(CGRect(x: -10, y: 3.4, width: 20, height: 6)), with: .color(Palette.clay.base))
            var seam = Path()
            seam.move(to: CGPoint(x: -8.5, y: 3.4))
            seam.addLine(to: CGPoint(x: 8.5, y: 3.4))
            bootInk.crease(seam, in: sole, width: 0.9, opacity: 0.5)
        }
    }

    private func drawTorso(in context: GraphicsContext, ink: Ink) {
        let neck = Path(roundedRect: CGRect(x: 64, y: 113, width: 16, height: 11), cornerRadius: 3)
        ink.paint(neck, Palette.joint, in: context)

        let rect = CGRect(x: 51, y: 121, width: 42, height: 37)
        let torso = Path(roundedRect: rect, cornerRadius: 15, style: .continuous)
        ink.paint(torso, Palette.shell, in: context)

        var band = context
        band.clip(to: torso)
        let belt = Path(CGRect(x: rect.minX, y: 146, width: rect.width, height: 5.5))
        band.fill(belt, with: .color(Palette.clay.base))
        band.fill(Path(CGRect(x: rect.minX, y: 150, width: rect.width, height: 1.5)), with: .color(Palette.clay.shade))
        ink.crease(belt, in: band, width: 0.8, opacity: 0.35)

        // Claude's spark on the chest, in a shallow round badge.
        let badge = CGPoint(x: 72, y: 134)
        band.fill(Circle().path(in: CGRect(center: badge, radius: 7.8)), with: .color(Palette.shell.shade))
        band.fill(Circle().path(in: CGRect(center: badge + CGPoint(x: -0.5, y: -0.6), radius: 7)), with: .color(Palette.shell.base))
        band.fill(SparkShape().path(in: CGRect(center: badge, radius: 6.4)), with: .color(Palette.clay.base))
        ink.gloss(CGRect(x: rect.minX + 7, y: rect.minY + 4, width: 12, height: 5), in: band, opacity: 0.7, angle: -20)
    }

    // MARK: Head

    private static let shell = CGRect(x: 30, y: 52, width: 84, height: 68)
    private static let visor = CGRect(x: 39, y: 63, width: 66, height: 46)

    private func drawHead(in context: GraphicsContext, ink: Ink) {
        for x in [25.0, 110.0] {
            let cap = Path(roundedRect: CGRect(x: x, y: 75, width: 9, height: 22), cornerRadius: 4, style: .continuous)
            ink.paint(cap, Palette.clay, in: context)
            var groove = Path()
            groove.move(to: CGPoint(x: x + 4.5, y: 80))
            groove.addLine(to: CGPoint(x: x + 4.5, y: 92))
            ink.crease(groove, in: context, width: 1, opacity: 0.45)
        }

        let dome = Ellipse().path(in: CGRect(x: 63, y: 48, width: 18, height: 9))
        ink.paint(dome, Palette.shell, in: context)

        let shellPath = Path(roundedRect: Self.shell, cornerRadius: 30, style: .continuous)
        ink.paint(shellPath, Palette.shell, in: context)
        ink.gloss(CGRect(x: 42, y: 56, width: 26, height: 7), in: context, opacity: 0.85, angle: -10)

        // The visor sits in a shallow bezel, glass catching two streaks of light.
        let bezel = Path(roundedRect: Self.visor.insetBy(dx: -2.4, dy: -2.4), cornerRadius: 21, style: .continuous)
        context.fill(bezel, with: .color(Palette.shell.shade))
        let visorPath = Path(roundedRect: Self.visor, cornerRadius: 19, style: .continuous)
        context.fill(visorPath, with: .linearGradient(
            Gradient(colors: [Palette.visorTop, Palette.visorBottom]),
            startPoint: CGPoint(x: Self.visor.midX, y: Self.visor.minY), endPoint: CGPoint(x: Self.visor.midX, y: Self.visor.maxY)
        ))
        ink.crease(visorPath, in: context, width: 1.2, opacity: 0.9)

        var glass = context
        glass.clip(to: visorPath)
        drawFace(in: glass)
        for (x, width, opacity) in [(Self.visor.minX + 40, 9.0, 0.10), (Self.visor.minX + 53, 4.0, 0.08)] {
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: Self.visor.minY))
            streak.addLine(to: CGPoint(x: x + width, y: Self.visor.minY))
            streak.addLine(to: CGPoint(x: x + width - 22, y: Self.visor.maxY))
            streak.addLine(to: CGPoint(x: x - 22, y: Self.visor.maxY))
            streak.closeSubpath()
            glass.fill(streak, with: .color(.white.opacity(opacity)))
        }
    }

    private func drawFace(in context: GraphicsContext) {
        let left = CGPoint(x: 59, y: 84), right = CGPoint(x: 85, y: 84)
        let mouth = CGPoint(x: 72, y: 99)

        if [.delighted, .tickled, .excited].contains(mood) {
            for eye in [left, right] {
                context.fill(Ellipse().path(in: CGRect(center: eye + CGPoint(x: 0, y: 10), width: 10, height: 4.5)),
                             with: .color(Palette.blush.opacity(0.6)))
            }
        }

        var glow = context
        glow.addFilter(.shadow(color: Palette.glow, radius: 3.5))
        let led = GraphicsContext.Shading.color(Palette.led)
        let line = StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)

        for (index, eye) in [left, right].enumerated() {
            let side: CGFloat = index == 0 ? -1 : 1
            switch mood {
            case .cheerful:
                var open = glow
                open.translateBy(x: eye.x, y: eye.y)
                open.scaleBy(x: 1, y: blink)
                open.fill(Path(roundedRect: CGRect(x: -3.6, y: -6.5, width: 7.2, height: 13), cornerRadius: 3.6), with: led)
            case .excited:
                var star = glow
                star.translateBy(x: eye.x, y: eye.y)
                star.rotate(by: .degrees(12 * sin(time * 4) * Double(side)))
                star.scaleBy(x: 1 + 0.08 * sin(time * 8), y: 1 + 0.08 * sin(time * 8))
                star.fill(SparkShape(rays: 4, innerRatio: 0.3).path(in: CGRect(center: .zero, radius: 9)), with: led)
            case .pleading:
                var open = glow
                open.translateBy(x: eye.x, y: eye.y)
                open.scaleBy(x: 1, y: blink)
                open.fill(Ellipse().path(in: CGRect(x: -6, y: -6.5, width: 12, height: 13)), with: led)
                open.fill(Circle().path(in: CGRect(center: CGPoint(x: -2.2, y: -2.6), radius: 2.2)), with: .color(.white))
                open.fill(Circle().path(in: CGRect(center: CGPoint(x: 2.2, y: 2.4), radius: 1.1)), with: .color(.white))
                var brow = Path()
                brow.move(to: eye + CGPoint(x: -5 * side, y: -13.5))
                brow.addLine(to: eye + CGPoint(x: 4.5 * side, y: -9.5))
                glow.stroke(brow, with: led, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            case .thirsty:
                // Heavy lids sloping down to the outside: droopy and parched.
                var lidded = glow
                var below = Path()
                below.move(to: eye + CGPoint(x: -9, y: side < 0 ? 0.5 : -2.5))
                below.addLine(to: eye + CGPoint(x: 9, y: side < 0 ? -2.5 : 0.5))
                below.addLine(to: eye + CGPoint(x: 9, y: 10))
                below.addLine(to: eye + CGPoint(x: -9, y: 10))
                below.closeSubpath()
                lidded.clip(to: below)
                lidded.fill(Path(roundedRect: CGRect(center: eye, width: 9, height: 12), cornerRadius: 4.5), with: led)
            case .delighted:
                var arc = Path()
                arc.move(to: eye + CGPoint(x: -5.5, y: 2.5))
                arc.addQuadCurve(to: eye + CGPoint(x: 5.5, y: 2.5), control: eye + CGPoint(x: 0, y: -7))
                glow.stroke(arc, with: led, style: line)
            case .sleepy:
                var shut = Path()
                shut.move(to: eye + CGPoint(x: -5.5, y: 0))
                shut.addQuadCurve(to: eye + CGPoint(x: 5.5, y: 0), control: eye + CGPoint(x: 0, y: 5))
                glow.stroke(shut, with: led, style: line)
            case .tickled:
                var chevron = Path()
                chevron.move(to: eye + CGPoint(x: -4 * side, y: -4.5))
                chevron.addLine(to: eye + CGPoint(x: 4 * side, y: 0))
                chevron.addLine(to: eye + CGPoint(x: -4 * side, y: 4.5))
                glow.stroke(chevron, with: led, style: line)
            }
        }

        let thin = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        switch mood {
        case .cheerful:
            var smile = Path()
            smile.move(to: mouth + CGPoint(x: -4.5, y: -1.5))
            smile.addQuadCurve(to: mouth + CGPoint(x: 4.5, y: -1.5), control: mouth + CGPoint(x: 0, y: 3.5))
            glow.stroke(smile, with: led, style: thin)
        case .excited, .delighted, .tickled:
            let width: CGFloat = mood == .excited ? 5.5 : 6.5
            var grin = Path()
            grin.move(to: mouth + CGPoint(x: -width, y: -2.5))
            grin.addLine(to: mouth + CGPoint(x: width, y: -2.5))
            grin.addQuadCurve(to: mouth + CGPoint(x: -width, y: -2.5), control: mouth + CGPoint(x: 0, y: 8 + (mood == .tickled ? 1.5 * sin(time * 20) : 0)))
            glow.fill(grin, with: led)
        case .pleading:
            glow.stroke(Ellipse().path(in: CGRect(center: mouth, width: 4, height: 4.6)), with: led, lineWidth: 1.8)
        case .thirsty:
            var wave = Path()
            wave.move(to: mouth + CGPoint(x: -6, y: 0))
            wave.addQuadCurve(to: mouth, control: mouth + CGPoint(x: -3, y: -3))
            wave.addQuadCurve(to: mouth + CGPoint(x: 6, y: 0), control: mouth + CGPoint(x: 3, y: 3))
            glow.stroke(wave, with: led, style: thin)
        case .sleepy:
            let snore = 2.4 + 1.2 * sin(time * 2)
            glow.fill(Ellipse().path(in: CGRect(center: mouth, width: snore, height: snore)), with: led)
        }
    }

    /// Sweat when thirsty, floating z's when sleepy.
    private func drawMoodExtras(in context: GraphicsContext) {
        let shell = Self.shell
        switch mood {
        case .thirsty:
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: shell.maxX - 4, y: shell.minY + 10 + drip * 12)
            let drop = DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11))
            var sweat = context
            sweat.opacity = 1 - drip * 0.6
            sweat.stroke(drop, with: .color(Palette.ink), lineWidth: 2)
            sweat.fill(drop, with: .color(Bottle.water))
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: shell.maxX + 4 + phase * 14, y: shell.minY + 4 - phase * 24)
                var snore = context
                snore.opacity = sin(phase * .pi)
                snore.draw(
                    Text("z").font(.system(size: 9 + phase * 6, weight: .heavy, design: .rounded)).foregroundColor(Palette.shell.base),
                    at: point
                )
            }
        default:
            break
        }
    }

    // MARK: Arms

    private func drawArm(in context: GraphicsContext, ink: Ink, from shoulder: CGPoint, to hand: CGPoint, bend: CGFloat, handAngle: Double, thumb: CGFloat) {
        let control = Sketch.elbow(shoulder, hand, bend: bend)
        let arm = Sketch.limb(shoulder, control, hand, 4.6, 3.9)
        ink.paint(arm, Palette.shell, in: context)
        // A clay cuff at the wrist.
        let wrist = Sketch.quad(shoulder, control, hand, 0.78)
        let along = (hand - control).normalized
        var cuff = Path()
        cuff.move(to: wrist + CGPoint(x: -along.y, y: along.x) * 4.4)
        cuff.addLine(to: wrist - CGPoint(x: -along.y, y: along.x) * 4.4)
        context.stroke(cuff, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 4.6, lineCap: .round))
        context.stroke(cuff, with: .color(Palette.clay.base), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        // Ball joint peeking out at the shoulder.
        ink.paint(Circle().path(in: CGRect(center: shoulder, radius: 4.2)), Palette.joint, in: context)
    }

    private func drawHand(in context: GraphicsContext, ink: Ink, at point: CGPoint, angle: Double, thumb: CGFloat) {
        let hand = Sketch.mitten(at: point, radius: 5.6, angle: angle, thumb: thumb)
        ink.paint([(hand.thumb, Palette.shell), (hand.palm, Palette.shell)], in: context)
    }

    /// The free hand (the bot's right): waving, pumping, pleading, or limp.
    private func freeHand(motion: Motion) -> (point: CGPoint, angle: Double, bend: CGFloat) {
        let shoulder = Self.leftShoulder
        let t = time
        switch mood {
        case .cheerful:
            let reach = CGPoint(x: -27, y: -27).rotated(by: 14 * sin(t * 5.5))
            return (shoulder + reach, -110 + 14 * sin(t * 5.5), 0.22)
        case .excited:
            return (shoulder + CGPoint(x: -27, y: -33 - 3 * abs(sin(t * 6))), -105, 0.2)
        case .pleading:
            return (shoulder + CGPoint(x: -26, y: -2 + 1.5 * sin(t * 1.4)), 200, -0.2)
        case .thirsty:
            return (shoulder + CGPoint(x: -10, y: 29), 100, -0.12)
        case .delighted:
            let reach = CGPoint(x: -29, y: -30).rotated(by: 10 * sin(t * 9))
            return (shoulder + reach, -105, 0.22)
        case .sleepy:
            return (shoulder + CGPoint(x: -8, y: 30), 95, -0.1)
        case .tickled:
            return (CGPoint(x: 70, y: 106) + CGPoint(x: 1.5 * sin(t * 22), y: 0), -60, -0.3)
        }
    }

    // MARK: Bottle

    /// Bottle center and tilt, eased between "at its side" and "at the visor".
    private func bottlePose(wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let angle = 8 + (-100 - 8) * Double(eased) + wiggle
        let rest = CGPoint(x: 124, y: 152)
        let drinking = Self.mouth - Bottle.offset(Bottle.neck, angle: -100)
        let center = rest + (drinking - rest) * eased
        return (center, angle)
    }

    // MARK: Motion

    /// Open eyes blink every few seconds.
    private var blink: CGFloat {
        time.truncatingRemainder(dividingBy: 3.8) > 3.66 ? 0.12 : 1
    }

    /// Per-mood body language: how it swings, kicks, tilts and bounces.
    private struct Motion {
        var swing = 0.0
        var lift: CGFloat = 0
        /// The whole bot turning on its antenna ring.
        var tilt = 0.0
        var legLeft = 0.0
        var legRight = 0.0
        /// Extra bottle rotation, for shaking it at you.
        var wiggle = 0.0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 4 * sin(t * 1.7)
                tilt = 3 * sin(t * 1.3 + 0.5)
                legLeft = 14 * sin(t * 2.6)
                legRight = 14 * sin(t * 2.6 + 1.3)
            case .excited:
                swing = 1.2 * sin(t * 2)
                lift = -4 * abs(sin(t * 6))
                tilt = 3 * sin(t * 3)
                legLeft = 22 * sin(t * 7)
                legRight = 22 * sin(t * 7 + .pi)
            case .pleading:
                swing = 2.5 * sin(t * 1.5)
                tilt = 7 + 2 * sin(t * 1.2)
                legLeft = 6 * sin(t * 2)
                legRight = 6 * sin(t * 2 + 1)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 2
                tilt = -7 + 1.5 * sin(t * 0.8)
                legLeft = 3 * sin(t * 0.9)
                legRight = 3 * sin(t * 0.9 + 0.8)
            case .delighted:
                swing = 5 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                tilt = 4 * sin(t * 3)
                legLeft = 18 * sin(t * 6)
                legRight = 18 * sin(t * 6 + .pi)
            case .sleepy:
                swing = 1.5 * sin(t * 0.7)
                tilt = -9 + 2 * sin(t * 0.9)
                legLeft = 2 * sin(t * 0.7)
                legRight = 2 * sin(t * 0.7 + 0.5)
            case .tickled:
                swing = 6 * sin(t * 26)
                lift = -3
                tilt = 8 * sin(t * 18)
                legLeft = 26 * sin(t * 12)
                legRight = 26 * sin(t * 12 + .pi)
            }
        }
    }

    enum Palette {
        static let ink = Color(hex: 0x33241D)
        static let inkStyle = Ink(color: ink)
        static let shell = Tone(0xF5F0E6, shade: 0xD9CCBA, light: 0xFFFFFF)
        static let clay = Tone(0xD97757, shade: 0xB65A3B, light: 0xF0A587)
        static let joint = Tone(0x4A3F3A, shade: 0x2E2724, light: 0x6E625B)
        static let steel = Color(hex: 0xB9B3AC)
        static let visorTop = Color(hex: 0x2E2622)
        static let visorBottom = Color(hex: 0x0D0A09)
        static let led = Color(hex: 0xFFD9B0)
        static let glow = Color(hex: 0xE8916F)
        static let blush = Color(hex: 0xE8916F)
        static let bottle = Bottle(cap: clay, label: Color(hex: 0xD97757))
    }
}

#Preview {
    TimelineView(.animation) { context in
        let time = context.date.timeIntervalSinceReferenceDate
        HStack(spacing: 8) {
            ForEach(WaterBotMood.allCases, id: \.self) { mood in
                WaterBotFigure(mood: mood, time: time)
            }
        }
    }
    .padding(30)
    .background(Color(hex: 0x2A2438))
}
