import SwiftUI

/// The water bot, drawn in code: a little ivory-and-clay robot hanging from a
/// braided rope with a bottle in its other hand. Everything is a function of
/// `mood` and `time`, so wrapping it in a `TimelineView` animates it.
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
    static let ropeAnchor = CGPoint(x: 56, y: 0)

    var body: some View {
        let motion = Motion(mood: mood, time: time)
        Canvas { context, _ in
            draw(in: context, motion: motion)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: Theme.Palette.clay.opacity(0.45), radius: 14)
        .shadow(color: .black.opacity(0.35), radius: 5, y: 4)
        .rotationEffect(
            .degrees(motion.swing),
            anchor: UnitPoint(x: Self.ropeAnchor.x / Self.size.width, y: 0)
        )
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, motion: Motion) {
        let lift = CGPoint(x: 0, y: motion.lift)
        let ropeHand = CGPoint(x: Self.ropeAnchor.x, y: 52) + lift
        let neck = CGPoint(x: 84, y: 140) + lift

        drawRope(in: context, to: ropeHand)
        drawArm(in: context, from: CGPoint(x: 62, y: 134) + lift, control: CGPoint(x: 2, y: 80) + lift, to: ropeHand + CGPoint(x: 0, y: 4))
        drawLegs(in: context, motion: motion, lift: lift)
        drawTorso(in: context, lift: lift)

        var head = context
        head.translateBy(x: neck.x, y: neck.y)
        head.rotate(by: .degrees(motion.headTilt))
        head.translateBy(x: -neck.x, y: -neck.y)
        drawHead(in: head, lift: lift)

        let (bottleCenter, bottleAngle) = bottlePose(lift: lift, wiggle: motion.wiggle)
        // Grips the bottle's near side, fingers wrapped around the glass.
        let bottleHand = bottleCenter + rotated(CGPoint(x: -12, y: 4), by: bottleAngle)
        drawArm(in: context, from: CGPoint(x: 106, y: 152) + lift, control: CGPoint(x: 120, y: 166) + lift, to: bottleHand)
        drawBottle(in: context, center: bottleCenter, angle: bottleAngle)
        drawHand(in: context, at: bottleHand)
        drawHand(in: context, at: ropeHand)
        drawRopeGrip(in: context, at: ropeHand)
    }

    private func drawRope(in context: GraphicsContext, to end: CGPoint) {
        var rope = Path()
        rope.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        rope.addLine(to: end)
        context.stroke(rope, with: .color(Palette.clay), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // Diagonal braid: short dashes in a deeper clay read as twisted strands.
        context.stroke(rope, with: .color(Palette.clayDeep), style: StrokeStyle(lineWidth: 6, dash: [2.2, 3.2]))
        var shine = Path()
        shine.move(to: CGPoint(x: Self.ropeAnchor.x - 1.3, y: -6))
        shine.addLine(to: end + CGPoint(x: -1.3, y: 0))
        context.stroke(shine, with: .color(Palette.clayGlow.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [2, 3.4]))
    }

    private func drawArm(in context: GraphicsContext, from start: CGPoint, control: CGPoint, to end: CGPoint) {
        var arm = Path()
        arm.move(to: start)
        arm.addQuadCurve(to: end, control: control)
        context.stroke(arm, with: .color(Palette.charcoal), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        context.stroke(arm, with: .color(Palette.shell), style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
        // Elbow joint at the curve's midpoint.
        let elbow = CGPoint(
            x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x,
            y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y
        )
        context.fill(Circle().path(in: CGRect(center: elbow, radius: 5.5)), with: .color(Palette.charcoal))
        context.stroke(Circle().path(in: CGRect(center: elbow, radius: 5.5)), with: .color(Palette.clay), lineWidth: 1.6)
    }

    private func rotated(_ point: CGPoint, by degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians))
    }

    private func drawHand(in context: GraphicsContext, at point: CGPoint) {
        let hand = Circle().path(in: CGRect(center: point, radius: 7.5))
        context.fill(hand, with: .linearGradient(
            Gradient(colors: [Palette.shell, Palette.shellShade]),
            startPoint: point + CGPoint(x: -6, y: -6), endPoint: point + CGPoint(x: 6, y: 6)
        ))
        context.stroke(hand, with: .color(Palette.charcoal.opacity(0.35)), lineWidth: 1)
    }

    /// Fingers wrapped over the rope, drawn on top of it.
    private func drawRopeGrip(in context: GraphicsContext, at point: CGPoint) {
        for offset in [-3.0, 0.5, 4.0] {
            var finger = Path()
            finger.move(to: point + CGPoint(x: -6, y: offset))
            finger.addQuadCurve(to: point + CGPoint(x: 6, y: offset), control: point + CGPoint(x: 0, y: offset + 2.5))
            context.stroke(finger, with: .color(Palette.charcoal.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        let cuff = CGRect(x: point.x - 7, y: point.y + 7, width: 14, height: 4)
        context.fill(Capsule().path(in: cuff), with: .color(Palette.clay))
    }

    private func drawLegs(in context: GraphicsContext, motion: Motion, lift: CGPoint) {
        for (hip, angle) in [(CGPoint(x: 72, y: 170), motion.legLeft), (CGPoint(x: 96, y: 170), motion.legRight)] {
            let start = hip + lift
            let radians = angle * .pi / 180
            let foot = start + CGPoint(x: -sin(radians) * 17, y: cos(radians) * 17)
            var leg = Path()
            leg.move(to: start)
            leg.addLine(to: foot)
            context.stroke(leg, with: .color(Palette.charcoal), style: StrokeStyle(lineWidth: 9, lineCap: .round))

            var boot = context
            boot.translateBy(x: foot.x, y: foot.y)
            boot.rotate(by: .degrees(angle))
            let shape = Ellipse().path(in: CGRect(x: -10, y: -3, width: 20, height: 13))
            boot.fill(shape, with: .linearGradient(
                Gradient(colors: [Palette.shell, Palette.shellShade]),
                startPoint: CGPoint(x: 0, y: -3), endPoint: CGPoint(x: 0, y: 10)
            ))
            boot.stroke(shape, with: .color(Palette.clay), lineWidth: 2.4)
        }
    }

    private func drawTorso(in context: GraphicsContext, lift: CGPoint) {
        let rect = CGRect(x: 58, y: 136, width: 52, height: 40).offsetBy(dx: 0, dy: lift.y)
        let torso = RoundedRectangle(cornerRadius: 16, style: .continuous).path(in: rect)
        context.fill(torso, with: .linearGradient(
            Gradient(colors: [Palette.shell, Palette.shellShade]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        var belt = context
        belt.clip(to: torso)
        belt.fill(Path(CGRect(x: rect.minX, y: rect.minY + 23, width: rect.width, height: 7)), with: .color(Palette.clay))
        context.stroke(torso, with: .color(Palette.charcoal.opacity(0.25)), lineWidth: 1)

        var light = context
        light.addFilter(.shadow(color: Palette.clayGlow, radius: 4))
        light.fill(Circle().path(in: CGRect(center: CGPoint(x: rect.midX, y: rect.minY + 12), radius: 3.6)), with: .color(Palette.eye))
    }

    // MARK: Head

    private func drawHead(in context: GraphicsContext, lift: CGPoint) {
        for center in [CGPoint(x: 36, y: 106), CGPoint(x: 132, y: 106)] {
            let pod = center + lift
            context.fill(Circle().path(in: CGRect(center: pod, radius: 13.5)), with: .linearGradient(
                Gradient(colors: [Palette.clayGlow, Palette.clayDeep]),
                startPoint: pod + CGPoint(x: -8, y: -10), endPoint: pod + CGPoint(x: 8, y: 10)
            ))
            context.fill(Circle().path(in: CGRect(center: pod, radius: 6.5)), with: .color(Palette.charcoal))
        }

        let shell = CGRect(x: 37, y: 64, width: 94, height: 80).offsetBy(dx: 0, dy: lift.y)
        let shellPath = RoundedRectangle(cornerRadius: 34, style: .continuous).path(in: shell)
        context.fill(shellPath, with: .linearGradient(
            Gradient(colors: [Palette.shell, Palette.shellShade]),
            startPoint: CGPoint(x: shell.minX, y: shell.minY), endPoint: CGPoint(x: shell.maxX, y: shell.maxY)
        ))
        context.stroke(shellPath, with: .color(Palette.charcoal.opacity(0.25)), lineWidth: 1)
        // Soft top highlight, like the glossy toy plastic in the reference art.
        context.fill(
            Ellipse().path(in: CGRect(x: shell.minX + 18, y: shell.minY + 5, width: 40, height: 10)),
            with: .color(.white.opacity(0.55))
        )

        let forehead = CGRect(center: CGPoint(x: 84, y: 76) + lift, radius: 7.5)
        context.fill(SparkShape().path(in: forehead), with: .color(Palette.clay))

        let visor = CGRect(x: 52, y: 87, width: 68, height: 46).offsetBy(dx: 0, dy: lift.y)
        let visorPath = RoundedRectangle(cornerRadius: 19, style: .continuous).path(in: visor)
        context.fill(visorPath, with: .linearGradient(
            Gradient(colors: [Palette.visorTop, Palette.visorBottom]),
            startPoint: CGPoint(x: visor.midX, y: visor.minY), endPoint: CGPoint(x: visor.midX, y: visor.maxY)
        ))
        context.stroke(visorPath, with: .color(.white.opacity(0.10)), lineWidth: 1)
        var gloss = context
        gloss.clip(to: visorPath)
        gloss.fill(
            Ellipse().path(in: CGRect(x: visor.minX + 6, y: visor.minY + 3, width: 30, height: 9)),
            with: .color(.white.opacity(0.09))
        )

        drawFace(in: context, visor: visor)
        drawMoodExtras(in: context, shell: shell)
    }

    private func drawFace(in context: GraphicsContext, visor: CGRect) {
        var face = context
        face.clip(to: RoundedRectangle(cornerRadius: 19, style: .continuous).path(in: visor))
        let left = CGPoint(x: visor.minX + 21, y: visor.minY + 20)
        let right = CGPoint(x: visor.maxX - 21, y: visor.minY + 20)
        let mouth = CGPoint(x: visor.midX, y: visor.minY + 35)

        if [.delighted, .tickled, .excited].contains(mood) {
            for eye in [left, right] {
                face.fill(
                    Ellipse().path(in: CGRect(x: eye.x - 6, y: eye.y + 7, width: 12, height: 5)),
                    with: .color(Palette.clay.opacity(0.55))
                )
            }
        }

        var glow = face
        glow.addFilter(.shadow(color: Palette.clayGlow, radius: 4.5))
        let line = StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(Palette.eye)

        for (index, eye) in [left, right].enumerated() {
            let side: CGFloat = index == 0 ? -1 : 1
            switch mood {
            case .cheerful, .delighted:
                var arc = Path()
                arc.move(to: eye + CGPoint(x: -6.5, y: 3))
                arc.addQuadCurve(to: eye + CGPoint(x: 6.5, y: 3), control: eye + CGPoint(x: 0, y: -8))
                glow.stroke(arc, with: ink, style: line)
            case .excited:
                var star = glow
                star.translateBy(x: eye.x, y: eye.y)
                star.rotate(by: .degrees(time * 90 * Double(side)))
                star.fill(SparkShape(rays: 8, innerRatio: 0.26).path(in: CGRect(center: .zero, radius: 9.5)), with: ink)
            case .pleading:
                var open = glow
                open.translateBy(x: eye.x, y: eye.y)
                open.scaleBy(x: 1, y: blink)
                open.fill(Ellipse().path(in: CGRect(x: -6.5, y: -7.5, width: 13, height: 15)), with: ink)
                open.fill(Circle().path(in: CGRect(center: CGPoint(x: -2.2, y: -3.2), radius: 2.6)), with: .color(.white))
                open.fill(Circle().path(in: CGRect(center: CGPoint(x: 2.4, y: 3), radius: 1.3)), with: .color(.white))
            case .thirsty:
                // Heavy lids that slope down toward the outside: sad and droopy.
                var lid = glow
                var below = Path()
                below.move(to: eye + CGPoint(x: -9, y: side < 0 ? 0 : -3))
                below.addLine(to: eye + CGPoint(x: 9, y: side < 0 ? -3 : 0))
                below.addLine(to: eye + CGPoint(x: 9, y: 10))
                below.addLine(to: eye + CGPoint(x: -9, y: 10))
                below.closeSubpath()
                lid.clip(to: below)
                lid.fill(Ellipse().path(in: CGRect(x: eye.x - 6.5, y: eye.y - 5, width: 13, height: 12)), with: ink)
            case .sleepy:
                var shut = Path()
                shut.move(to: eye + CGPoint(x: -6, y: 1))
                shut.addQuadCurve(to: eye + CGPoint(x: 6, y: 1), control: eye + CGPoint(x: 0, y: 5))
                glow.stroke(shut, with: ink, style: line)
            case .tickled:
                var chevron = Path()
                chevron.move(to: eye + CGPoint(x: -4.5 * side, y: -5))
                chevron.addLine(to: eye + CGPoint(x: 4.5 * side, y: 0))
                chevron.addLine(to: eye + CGPoint(x: -4.5 * side, y: 5))
                glow.stroke(chevron, with: ink, style: line)
            }
        }

        let thin = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        switch mood {
        case .cheerful:
            var smile = Path()
            smile.move(to: mouth + CGPoint(x: -4, y: -1))
            smile.addQuadCurve(to: mouth + CGPoint(x: 4, y: -1), control: mouth + CGPoint(x: 0, y: 3.5))
            glow.stroke(smile, with: ink, style: thin)
        case .delighted, .excited, .tickled:
            let width: CGFloat = mood == .excited ? 5 : 6.5
            var grin = Path()
            grin.move(to: mouth + CGPoint(x: -width, y: -2))
            grin.addLine(to: mouth + CGPoint(x: width, y: -2))
            grin.addQuadCurve(to: mouth + CGPoint(x: -width, y: -2), control: mouth + CGPoint(x: 0, y: 9))
            glow.fill(grin, with: ink)
        case .pleading:
            glow.stroke(Ellipse().path(in: CGRect(x: mouth.x - 2, y: mouth.y - 3, width: 4, height: 4.5)), with: ink, lineWidth: 1.8)
        case .thirsty:
            var wave = Path()
            wave.move(to: mouth + CGPoint(x: -6, y: 0))
            wave.addQuadCurve(to: mouth + CGPoint(x: 0, y: 0), control: mouth + CGPoint(x: -3, y: -3))
            wave.addQuadCurve(to: mouth + CGPoint(x: 6, y: 0), control: mouth + CGPoint(x: 3, y: 3))
            glow.stroke(wave, with: ink, style: thin)
        case .sleepy:
            let snore = 2 + 1.2 * sin(time * 2)
            glow.fill(Ellipse().path(in: CGRect(x: mouth.x - snore / 2, y: mouth.y - 2, width: snore, height: snore)), with: ink)
        }
    }

    /// Sweat when thirsty, floating z's when sleepy.
    private func drawMoodExtras(in context: GraphicsContext, shell: CGRect) {
        switch mood {
        case .thirsty:
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: shell.maxX - 6, y: shell.minY + 14 + drip * 10)
            context.fill(DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11)),
                         with: .color(Palette.water.opacity(1 - drip * 0.6)))
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: shell.maxX + 2 + phase * 16, y: shell.minY + 6 - phase * 26)
                let size = 9 + phase * 6
                var snore = context
                snore.opacity = sin(phase * .pi)
                snore.draw(
                    Text("z").font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(Palette.shell),
                    at: point
                )
            }
        default:
            break
        }
    }

    // MARK: Bottle

    /// Bottle center and tilt, eased between "at its side" and "at the visor".
    private func bottlePose(lift: CGPoint, wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let rest = CGPoint(x: 138, y: 150), mouth = CGPoint(x: 124, y: 116)
        let center = CGPoint(x: rest.x + (mouth.x - rest.x) * eased, y: rest.y + (mouth.y - rest.y) * eased) + lift
        return (center, 10 + (-112 - 10) * Double(eased) + wiggle)
    }

    private func drawBottle(in context: GraphicsContext, center: CGPoint, angle: Double) {
        var bottle = context
        bottle.translateBy(x: center.x, y: center.y)
        bottle.rotate(by: .degrees(angle))

        let body = RoundedRectangle(cornerRadius: 9, style: .continuous).path(in: CGRect(x: -13, y: -17, width: 26, height: 40))
        let neck = RoundedRectangle(cornerRadius: 3, style: .continuous).path(in: CGRect(x: -7, y: -24, width: 14, height: 9))
        bottle.fill(body, with: .color(.white.opacity(0.18)))
        bottle.fill(neck, with: .color(.white.opacity(0.18)))

        // Water with a sloshing surface, and a few bubbles rising through it.
        let height = 38 * max(0, min(1, waterLevel))
        if height > 0.5 {
            var water = bottle
            water.clip(to: body)
            let surface = 22 - height
            var fill = Path()
            fill.move(to: CGPoint(x: -14, y: 24))
            fill.addLine(to: CGPoint(x: -14, y: surface))
            for step in stride(from: -14.0, through: 14.0, by: 2) {
                fill.addLine(to: CGPoint(x: step, y: surface + 1.3 * sin(step / 4 + time * 5)))
            }
            fill.addLine(to: CGPoint(x: 14, y: 24))
            fill.closeSubpath()
            water.fill(fill, with: .linearGradient(
                Gradient(colors: [Palette.water.opacity(0.95), Palette.waterDeep.opacity(0.95)]),
                startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: 23)
            ))
            for index in 0..<4 {
                let rise = (time * 14 + Double(index) * 9.5).truncatingRemainder(dividingBy: Double(height))
                let bubble = CGPoint(x: -6 + Double(index) * 4, y: 21 - rise)
                water.stroke(Circle().path(in: CGRect(center: bubble, radius: 1.1 + Double(index % 2) * 0.6)),
                             with: .color(.white.opacity(0.75)), lineWidth: 0.8)
            }
        }

        bottle.stroke(body, with: .color(.white.opacity(0.85)), lineWidth: 1.3)
        bottle.stroke(neck, with: .color(.white.opacity(0.85)), lineWidth: 1.1)
        bottle.fill(Capsule().path(in: CGRect(x: -9, y: -12, width: 3, height: 28)), with: .color(.white.opacity(0.55)))

        let cap = RoundedRectangle(cornerRadius: 3, style: .continuous).path(in: CGRect(x: -9.5, y: -34, width: 19, height: 11))
        bottle.fill(cap, with: .linearGradient(
            Gradient(colors: [Palette.clayGlow, Palette.clayDeep]),
            startPoint: CGPoint(x: 0, y: -34), endPoint: CGPoint(x: 0, y: -23)
        ))
        for ridge in stride(from: -6.0, through: 6.0, by: 3) {
            var line = Path()
            line.move(to: CGPoint(x: ridge, y: -32))
            line.addLine(to: CGPoint(x: ridge, y: -25))
            bottle.stroke(line, with: .color(Palette.clayDeep.opacity(0.8)), lineWidth: 1)
        }
    }

    // MARK: Motion

    /// Pleading eyes blink every few seconds.
    private var blink: CGFloat {
        time.truncatingRemainder(dividingBy: 3.8) > 3.66 ? 0.12 : 1
    }

    /// Per-mood body language: how it swings, kicks, tilts and bounces.
    private struct Motion {
        var swing = 0.0
        var lift: CGFloat = 0
        var headTilt = 0.0
        var legLeft = 0.0
        var legRight = 0.0
        /// Extra bottle rotation, for shaking it at you.
        var wiggle = 0.0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 5 * sin(t * 1.7)
                headTilt = 3 * sin(t * 1.3 + 0.5)
                legLeft = 16 * sin(t * 2.6)
                legRight = 16 * sin(t * 2.6 + 1.3)
            case .excited:
                swing = 1.2 * sin(t * 2)
                lift = -4 * abs(sin(t * 6))
                headTilt = 4 * sin(t * 3)
                legLeft = 24 * sin(t * 7)
                legRight = 24 * sin(t * 7 + .pi)
            case .pleading:
                swing = 3 * sin(t * 1.5)
                headTilt = 8 + 2 * sin(t * 1.2)
                legLeft = 8 * sin(t * 2)
                legRight = 8 * sin(t * 2 + 1)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 2
                headTilt = -9 + 1.5 * sin(t * 0.8)
                legLeft = 3 * sin(t * 0.9)
                legRight = 3 * sin(t * 0.9 + 0.8)
            case .delighted:
                swing = 6 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                headTilt = 5 * sin(t * 3)
                legLeft = 20 * sin(t * 6)
                legRight = 20 * sin(t * 6 + .pi)
            case .sleepy:
                swing = 1.5 * sin(t * 0.7)
                headTilt = -12 + 3 * sin(t * 0.9)
                legLeft = 2 * sin(t * 0.7)
                legRight = 2 * sin(t * 0.7 + 0.5)
            case .tickled:
                swing = 7 * sin(t * 26)
                lift = -3
                headTilt = 10 * sin(t * 18)
                legLeft = 28 * sin(t * 12)
                legRight = 28 * sin(t * 12 + .pi)
            }
        }
    }

    enum Palette {
        static let clay = Theme.Palette.clay
        static let clayDeep = Theme.Palette.clayDeep
        static let clayGlow = Theme.Palette.clayGlow
        static let shell = Theme.Palette.ivory
        static let shellShade = Color(hex: 0xE2D4C2)
        static let charcoal = Color(hex: 0x2B2420)
        static let visorTop = Color(hex: 0x2E2622)
        static let visorBottom = Color(hex: 0x0D0A09)
        static let eye = Color(hex: 0xFFD9B0)
        static let water = Color(hex: 0xA8DEFF)
        static let waterDeep = Color(hex: 0x4FA6E6)
        static let ink = Color(hex: 0x2A1D17)
    }
}

/// A water droplet, point up.
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY - radius)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.45))
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.45))
        path.closeSubpath()
        return path
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
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
