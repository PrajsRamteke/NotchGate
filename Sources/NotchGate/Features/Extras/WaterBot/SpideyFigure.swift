import SwiftUI

/// The water bot's alter ego, drawn in code: a chibi web-slinger hanging
/// upside down from a web line, one hand on the web, the bottle in the other,
/// big round head at the bottom. Like `WaterBotFigure`, everything is a
/// function of `mood` and `time`, so a `TimelineView` animates it.
struct SpideyFigure: View {
    var mood: WaterBotMood
    /// Seconds since Spidey appeared; drives the bounce on the web and the idle motion.
    var time: TimeInterval
    /// 0 = bottle beside the head, 1 = tipped to the mouth.
    var sip: CGFloat = 0
    /// How full the bottle is, 0…1.
    var waterLevel: CGFloat = 0.8

    /// Same frame and anchor as the robot, so the stage lays them out alike.
    static let size = WaterBotFigure.size
    static let ropeAnchor = WaterBotFigure.ropeAnchor
    /// Where the bottle meets the mouth, for the splash when you drink.
    static let mouth = CGPoint(x: 84, y: 122)

    var body: some View {
        let motion = Motion(mood: mood, time: time)
        Canvas { context, _ in
            draw(in: context, motion: motion)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: Palette.red.opacity(0.4), radius: 14)
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
        let webHand = CGPoint(x: Self.ropeAnchor.x, y: 58) + lift

        drawWeb(in: context, to: webHand + CGPoint(x: 0, y: 14))
        drawArm(in: context, from: CGPoint(x: 70, y: 98) + lift, control: CGPoint(x: 30, y: 86) + lift, to: webHand + CGPoint(x: 0, y: 3))
        drawLegs(in: context, motion: motion, lift: lift)
        drawTorso(in: context, lift: lift)

        let center = CGPoint(x: 84, y: 146) + lift
        var head = context
        head.translateBy(x: center.x, y: center.y)
        head.rotate(by: .degrees(180 + motion.headTilt))
        drawHead(in: head)
        drawMoodExtras(in: context, head: center)

        let (bottleCenter, bottleAngle) = bottlePose(lift: lift, wiggle: motion.wiggle)
        let bottleHand = bottleCenter + rotated(CGPoint(x: -12, y: 6), by: bottleAngle)
        drawArm(in: context, from: CGPoint(x: 98, y: 98) + lift, control: CGPoint(x: 150, y: 112) + lift, to: bottleHand)
        WaterBotFigure.drawBottle(
            in: context, center: bottleCenter, angle: bottleAngle, waterLevel: waterLevel, time: time,
            cap: (Palette.blueGlow, Palette.blueDeep)
        )
        drawGlove(in: context, at: bottleHand)
        drawGlove(in: context, at: webHand)
        drawWebGrip(in: context, at: webHand)
    }

    /// A silky strand from the notch, glinting as it sways.
    private func drawWeb(in context: GraphicsContext, to end: CGPoint) {
        var strand = Path()
        strand.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        strand.addLine(to: end)
        var glow = context
        glow.addFilter(.shadow(color: .white.opacity(0.8), radius: 3))
        glow.stroke(strand, with: .color(Palette.silk), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        // A second, finer fibre twisting around the first.
        var twist = Path()
        twist.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        for y in stride(from: -6.0, through: end.y, by: 3) {
            twist.addLine(to: CGPoint(x: Self.ropeAnchor.x + 1.4 * sin(y / 4 + time * 2), y: y))
        }
        context.stroke(twist, with: .color(Palette.silk.opacity(0.6)), lineWidth: 0.8)
        let glint = (time * 0.5).truncatingRemainder(dividingBy: 1) * max(1, end.y)
        context.fill(Circle().path(in: CGRect(center: CGPoint(x: Self.ropeAnchor.x, y: glint), radius: 1.8)),
                     with: .color(.white))
    }

    private func drawArm(in context: GraphicsContext, from start: CGPoint, control: CGPoint, to end: CGPoint) {
        var arm = Path()
        arm.move(to: start)
        arm.addQuadCurve(to: end, control: control)
        context.stroke(arm, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 11.5, lineCap: .round))
        context.stroke(arm, with: .color(Palette.red), style: StrokeStyle(lineWidth: 8, lineCap: .round))
    }

    private func drawGlove(in context: GraphicsContext, at point: CGPoint) {
        let glove = Circle().path(in: CGRect(center: point, radius: 7.5))
        context.fill(glove, with: .linearGradient(
            Gradient(colors: [Palette.redGlow, Palette.red, Palette.redDeep]),
            startPoint: point + CGPoint(x: -6, y: -6), endPoint: point + CGPoint(x: 6, y: 6)
        ))
        context.stroke(glove, with: .color(Palette.outline), lineWidth: 1.6)
        var lines = context
        lines.clip(to: glove)
        for angle in stride(from: 0.0, to: 360, by: 60) {
            var spoke = Path()
            spoke.move(to: point)
            spoke.addLine(to: point + rotated(CGPoint(x: 9, y: 0), by: angle))
            lines.stroke(spoke, with: .color(Palette.webInk.opacity(0.55)), lineWidth: 0.7)
        }
    }

    /// Fingers curled over the strand, drawn on top of it.
    private func drawWebGrip(in context: GraphicsContext, at point: CGPoint) {
        for offset in [-3.0, 0.5, 4.0] {
            var finger = Path()
            finger.move(to: point + CGPoint(x: -6, y: offset))
            finger.addQuadCurve(to: point + CGPoint(x: 6, y: offset), control: point + CGPoint(x: 0, y: offset + 2.5))
            context.stroke(finger, with: .color(Palette.outline.opacity(0.45)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    /// One leg hooked around the web, the other kicking free, boots up top.
    private func drawLegs(in context: GraphicsContext, motion: Motion, lift: CGPoint) {
        // Hooked leg: up and across, the ankle wrapped round the strand.
        let hip = CGPoint(x: 74, y: 66) + lift
        let knee = CGPoint(x: 84, y: 42) + lift
        let ankle = CGPoint(x: Self.ropeAnchor.x + 3, y: 26) + lift
        drawLeg(in: context, hip: hip, knee: knee, ankle: ankle, bootAngle: -150)
        for dy in [-3.0, 3.0] {
            let loop = CGRect(x: Self.ropeAnchor.x - 6, y: ankle.y + dy - 2, width: 12, height: 4.5)
            context.stroke(Ellipse().path(in: loop), with: .color(Palette.silk), lineWidth: 1.4)
        }

        // Free leg: bent at the knee, swinging with the mood.
        let freeHip = CGPoint(x: 94, y: 66) + lift
        let freeKnee = freeHip + rotated(CGPoint(x: 18, y: -20), by: motion.kick)
        let freeAnkle = freeKnee + rotated(CGPoint(x: -10, y: -18), by: motion.kick * 1.6)
        drawLeg(in: context, hip: freeHip, knee: freeKnee, ankle: freeAnkle, bootAngle: -70 + motion.kick * 1.6)
    }

    private func drawLeg(in context: GraphicsContext, hip: CGPoint, knee: CGPoint, ankle: CGPoint, bootAngle: Double) {
        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: knee)
        leg.addLine(to: ankle)
        let joint = StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
        context.stroke(leg, with: .color(Palette.outline), style: joint)
        context.stroke(leg, with: .linearGradient(
            Gradient(colors: [Palette.blueGlow, Palette.blue, Palette.blueDeep]),
            startPoint: hip, endPoint: ankle
        ), style: StrokeStyle(lineWidth: 9.5, lineCap: .round, lineJoin: .round))

        var boot = context
        boot.translateBy(x: ankle.x, y: ankle.y)
        boot.rotate(by: .degrees(bootAngle))
        let shape = Ellipse().path(in: CGRect(x: -4, y: -7, width: 20, height: 14))
        boot.fill(shape, with: .linearGradient(
            Gradient(colors: [Palette.redGlow, Palette.red, Palette.redDeep]),
            startPoint: CGPoint(x: 0, y: -7), endPoint: CGPoint(x: 0, y: 7)
        ))
        boot.stroke(shape, with: .color(Palette.outline), lineWidth: 1.6)
    }

    private func drawTorso(in context: GraphicsContext, lift: CGPoint) {
        let rect = CGRect(x: 64, y: 58, width: 40, height: 48).offsetBy(dx: 0, dy: lift.y)
        let torso = RoundedRectangle(cornerRadius: 17, style: .continuous).path(in: rect)
        context.fill(torso, with: .linearGradient(
            Gradient(colors: [Palette.redGlow, Palette.red, Palette.redDeep]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        var suit = context
        suit.clip(to: torso)
        // Blue flanks and briefs (at the top, since it's upside down).
        suit.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: 5, height: rect.height)), with: .color(Palette.blue))
        suit.fill(Path(CGRect(x: rect.maxX - 5, y: rect.minY, width: 5, height: rect.height)), with: .color(Palette.blue))
        suit.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 13)), with: .color(Palette.blue))
        var belt = Path()
        belt.move(to: CGPoint(x: rect.minX, y: rect.minY + 13))
        belt.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 13))
        suit.stroke(belt, with: .color(Palette.outline.opacity(0.6)), lineWidth: 1.2)
        context.stroke(torso, with: .color(Palette.outline), lineWidth: 1.6)

        // The chest spider, legs splayed, hanging the same way its wearer is.
        let chest = CGPoint(x: rect.midX, y: rect.maxY - 16)
        for side in [-1.0, 1.0] {
            for (index, angle) in [-50.0, -18, 18, 50].enumerated() {
                let bend = index < 2 ? 4.0 : -4.0
                var leg = Path()
                leg.move(to: chest)
                leg.addQuadCurve(
                    to: chest + rotated(CGPoint(x: 9 * side, y: 0), by: angle * side),
                    control: chest + rotated(CGPoint(x: 5 * side, y: bend), by: angle * side)
                )
                context.stroke(leg, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        context.fill(Ellipse().path(in: CGRect(x: chest.x - 2.6, y: chest.y - 4.5, width: 5.2, height: 9)), with: .color(Palette.outline))
        context.fill(Circle().path(in: CGRect(center: chest + CGPoint(x: 0, y: 6), radius: 2.2)), with: .color(Palette.outline))
    }

    // MARK: Head (drawn upright around the origin; the caller flips it)

    private static let headSize = CGSize(width: 98, height: 86)

    private func drawHead(in context: GraphicsContext) {
        let rect = CGRect(x: -Self.headSize.width / 2, y: -Self.headSize.height / 2,
                          width: Self.headSize.width, height: Self.headSize.height)
        let head = Ellipse().path(in: rect)
        // Lit from the world's top-left, which is this frame's bottom-right.
        context.fill(head, with: .radialGradient(
            Gradient(colors: [Palette.redGlow, Palette.red, Palette.redDeep]),
            center: CGPoint(x: 20, y: 22), startRadius: 4, endRadius: 70
        ))

        drawMaskWeb(in: context, clip: head, rect: rect)
        context.stroke(head, with: .color(Palette.outline), lineWidth: 1.8)
        context.fill(
            Ellipse().path(in: CGRect(x: 4, y: 26, width: 30, height: 9)),
            with: .color(.white.opacity(0.35))
        )

        drawFace(in: context)
    }

    /// Radial threads from the nose and scalloped rings between them.
    private func drawMaskWeb(in context: GraphicsContext, clip: Path, rect: CGRect) {
        var web = context
        web.clip(to: clip)
        let hub = CGPoint(x: 0, y: 6)
        let ink = GraphicsContext.Shading.color(Palette.webInk.opacity(0.55))
        let spokes = stride(from: -90.0, to: 270, by: 30).map { $0 }
        for angle in spokes {
            var spoke = Path()
            spoke.move(to: hub)
            spoke.addLine(to: hub + rotated(CGPoint(x: 80, y: 0), by: angle))
            web.stroke(spoke, with: ink, lineWidth: 0.9)
        }
        for radius in [16.0, 30, 45] {
            var ring = Path()
            for (index, angle) in (spokes + [spokes[0] + 360]).enumerated() {
                let point = hub + rotated(CGPoint(x: radius * 1.1, y: 0), by: angle)
                guard index > 0 else { ring.move(to: point); continue }
                let middle = hub + rotated(CGPoint(x: radius * 0.92, y: 0), by: angle - 15)
                ring.addQuadCurve(to: point, control: middle)
            }
            web.stroke(ring, with: ink, lineWidth: 0.9)
        }
    }

    private func drawFace(in context: GraphicsContext) {
        if [.cheerful, .delighted, .tickled, .excited].contains(mood) {
            for side in [-1.0, 1.0] {
                context.fill(
                    Ellipse().path(in: CGRect(x: 25 * side - 7, y: 17, width: 14, height: 6)),
                    with: .color(Palette.blush.opacity(0.75))
                )
            }
        }

        // No mouth: the mask hides it, and the eyes say it all.
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: 19 * side, y: 0)
            drawEye(in: context, at: eye, side: side)
        }
    }

    /// The big white lenses carry the mood: wide, sparkly, puppyish, droopy, squinting.
    private func drawEye(in context: GraphicsContext, at eye: CGPoint, side: CGFloat) {
        let thick = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(Palette.outline)

        switch mood {
        case .delighted:
            var arc = Path()
            arc.move(to: eye + CGPoint(x: -9, y: 4))
            arc.addQuadCurve(to: eye + CGPoint(x: 9, y: 4), control: eye + CGPoint(x: 0, y: -12))
            context.stroke(arc, with: ink, style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
            context.stroke(arc, with: .color(Palette.lens), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            return
        case .sleepy:
            var shut = Path()
            shut.move(to: eye + CGPoint(x: -10, y: 1))
            shut.addQuadCurve(to: eye + CGPoint(x: 10, y: 1), control: eye + CGPoint(x: 0, y: 7))
            context.stroke(shut, with: ink, style: thick)
            return
        case .tickled:
            var chevron = Path()
            chevron.move(to: eye + CGPoint(x: -6 * side, y: -7))
            chevron.addLine(to: eye + CGPoint(x: 6 * side, y: 0))
            chevron.addLine(to: eye + CGPoint(x: -6 * side, y: 7))
            context.stroke(chevron, with: ink, style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            context.stroke(chevron, with: .color(Palette.lens), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            return
        default:
            break
        }

        let lens = lensPath(at: eye, side: side)
        var open = context
        if mood == .pleading {
            // Blinks every few seconds.
            open.translateBy(x: eye.x, y: eye.y)
            open.scaleBy(x: 1, y: blink)
            open.translateBy(x: -eye.x, y: -eye.y)
        }
        open.fill(lens, with: .linearGradient(
            Gradient(colors: [Palette.lens, Palette.lensShade]),
            startPoint: eye + CGPoint(x: 0, y: 10), endPoint: eye + CGPoint(x: 0, y: -12)
        ))

        var inside = open
        inside.clip(to: lens)
        switch mood {
        case .excited:
            var star = inside
            star.translateBy(x: eye.x + 2 * side, y: eye.y)
            star.rotate(by: .degrees(time * 90 * Double(side)))
            star.fill(SparkShape(rays: 4, innerRatio: 0.32).path(in: CGRect(center: .zero, radius: 10)), with: ink)
        case .pleading:
            let pupil = eye + CGPoint(x: 1.5 * side, y: 1)
            inside.fill(Circle().path(in: CGRect(center: pupil, radius: 7.5)), with: ink)
            inside.fill(Circle().path(in: CGRect(center: pupil + CGPoint(x: 2.5, y: 3), radius: 2.6)), with: .color(.white))
            inside.fill(Circle().path(in: CGRect(center: pupil + CGPoint(x: -2.4, y: -2.6), radius: 1.3)), with: .color(.white))
        case .thirsty:
            // A heavy lid drooping toward the outside corner.
            var lid = Path()
            lid.move(to: eye + CGPoint(x: -30, y: -24))
            lid.addLine(to: eye + CGPoint(x: 30, y: -24))
            lid.addLine(to: eye + CGPoint(x: 30, y: -1 + 6 * side))
            lid.addLine(to: eye + CGPoint(x: -30, y: -1 - 6 * side))
            lid.closeSubpath()
            inside.fill(lid, with: .color(Palette.red))
            inside.stroke(lid, with: ink, lineWidth: 2.4)
        default:
            break
        }
        open.stroke(lens, with: ink, style: StrokeStyle(lineWidth: 3.4, lineJoin: .round))
    }

    /// A teardrop lens, tapered toward the nose, its rounded end swept outward.
    /// Drawn upright: the outer corner points up (+y is toward the chin here).
    private func lensPath(at eye: CGPoint, side: CGFloat) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { eye + CGPoint(x: x * side * 1.25, y: y * 1.25) }
        var path = Path()
        path.move(to: point(-12, 9))
        path.addCurve(to: point(13, -9), control1: point(-12, -7), control2: point(2, -14))
        path.addCurve(to: point(-12, 9), control1: point(22, -2), control2: point(6, 14))
        path.closeSubpath()
        return path
    }

    /// Sweat when thirsty, floating z's when sleepy (in world space, so they rise).
    private func drawMoodExtras(in context: GraphicsContext, head: CGPoint) {
        switch mood {
        case .thirsty:
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: head.x - 46, y: head.y - 8 + drip * 12)
            context.fill(DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11)),
                         with: .color(WaterBotFigure.Palette.water.opacity(1 - drip * 0.6)))
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: head.x - 50 - phase * 12, y: head.y + 10 - phase * 30)
                var snore = context
                snore.opacity = sin(phase * .pi)
                snore.draw(
                    Text("z").font(.system(size: 9 + phase * 6, weight: .heavy, design: .rounded)).foregroundColor(Palette.silk),
                    at: point
                )
            }
        default:
            break
        }
    }

    // MARK: Bottle

    /// Bottle center and tilt, eased between "beside the head" and "at the mouth".
    private func bottlePose(lift: CGPoint, wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let rest = CGPoint(x: 140, y: 164), mouth = CGPoint(x: 122, y: 112)
        let center = CGPoint(x: rest.x + (mouth.x - rest.x) * eased, y: rest.y + (mouth.y - rest.y) * eased) + lift
        return (center, 8 + (-78 - 8) * Double(eased) + wiggle)
    }

    private func rotated(_ point: CGPoint, by degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians))
    }

    // MARK: Motion

    private var blink: CGFloat {
        time.truncatingRemainder(dividingBy: 3.8) > 3.66 ? 0.12 : 1
    }

    /// Per-mood body language, plus a springy bounce on the web as Spidey arrives.
    private struct Motion {
        var swing = 0.0
        var lift: CGFloat = 0
        var headTilt = 0.0
        /// The free leg's swing, in degrees.
        var kick = 0.0
        var wiggle = 0.0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 5 * sin(t * 1.6)
                headTilt = 4 * sin(t * 1.3 + 0.5)
                kick = 14 * sin(t * 2.4)
            case .excited:
                swing = 2 * sin(t * 2)
                lift = -4 * abs(sin(t * 6))
                headTilt = 5 * sin(t * 3)
                kick = 24 * sin(t * 7)
            case .pleading:
                swing = 3 * sin(t * 1.5)
                headTilt = 9 + 2 * sin(t * 1.2)
                kick = 6 * sin(t * 2)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 3
                headTilt = -10 + 1.5 * sin(t * 0.8)
                kick = -10 + 3 * sin(t * 0.9)
            case .delighted:
                swing = 7 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                headTilt = 6 * sin(t * 3)
                kick = 22 * sin(t * 6)
            case .sleepy:
                swing = 1.5 * sin(t * 0.7)
                headTilt = -12 + 3 * sin(t * 0.9)
                kick = -16 + 2 * sin(t * 0.7)
            case .tickled:
                swing = 7 * sin(t * 26)
                lift = -3
                headTilt = 10 * sin(t * 18)
                kick = 30 * sin(t * 12)
            }
            // Bungee: Spidey drops in on the web and bobs until the strand settles.
            lift += CGFloat(10 * exp(-2.6 * t) * sin(t * 10))
        }
    }

    enum Palette {
        static let red = Color(hex: 0xE23A3F)
        static let redDeep = Color(hex: 0xA3161E)
        static let redGlow = Color(hex: 0xFF7A70)
        static let blue = Color(hex: 0x2F62D8)
        static let blueDeep = Color(hex: 0x173A94)
        static let blueGlow = Color(hex: 0x6C9BFF)
        static let outline = Color(hex: 0x2A0A0E)
        static let webInk = Color(hex: 0x5E0C12)
        static let lens = Color.white
        static let lensShade = Color(hex: 0xD8E2F1)
        static let blush = Color(hex: 0xFF9DB0)
        static let silk = Color(hex: 0xF3F5FA)
    }
}

#Preview {
    TimelineView(.animation) { context in
        let time = context.date.timeIntervalSinceReferenceDate
        HStack(spacing: 8) {
            ForEach(WaterBotMood.allCases, id: \.self) { mood in
                SpideyFigure(mood: mood, time: time)
            }
        }
    }
    .padding(30)
    .background(Color(hex: 0x2A2438))
}
