import SwiftUI

/// The water bot's web-slinging stand-in, drawn in code: a chibi Spider-Man
/// hanging upside down from a web tied round one ankle, the other leg hooked
/// behind it, in the classic red-and-blue suit. The mask's lenses squint and
/// widen with the mood, and he rolls the mask up to the nose to drink. Like
/// `WaterBotFigure`, everything is a function of `mood` and `time`.
struct SpideyFigure: View {
    var mood: WaterBotMood
    /// Seconds since Spidey appeared; drives the bounce on the web and the idle motion.
    var time: TimeInterval
    /// 0 = bottle beside the head, 1 = tipped to the mouth.
    var sip: CGFloat = 0
    /// How full the bottle is, 0…1.
    var waterLevel: CGFloat = 0.8

    static let size = WaterBotFigure.size
    /// Where the web leaves the top edge; Spidey swings around it.
    static let ropeAnchor = CGPoint(x: 64, y: 0)
    /// Where the bottle meets the mouth, for the splash when you drink.
    static let mouth = CGPoint(x: 78, y: 123)

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

    private static let ankle = CGPoint(x: 64, y: 32)
    private static let headCenter = CGPoint(x: 74, y: 152)
    private static let leftShoulder = CGPoint(x: 55, y: 113)
    private static let rightShoulder = CGPoint(x: 93, y: 113)

    private var ink: Ink { Palette.inkStyle }

    private func draw(in context: GraphicsContext, motion: Motion) {
        let lift = CGPoint(x: 0, y: motion.lift)
        drawWeb(in: context, to: Self.ankle + lift + CGPoint(x: 0, y: -4))

        var body = context
        body.translateBy(x: 0, y: lift.y)
        drawLegs(in: body, motion: motion)
        drawTorso(in: body)

        var head = body
        head.translateBy(x: Self.headCenter.x, y: Self.headCenter.y)
        head.rotate(by: .degrees(180 + motion.headTilt))
        drawHead(in: head, ink: ink.turned(by: 180 + motion.headTilt))
        drawMoodExtras(in: body)

        let (bottleCenter, bottleAngle) = bottlePose(wiggle: motion.wiggle)
        let grip = bottleCenter + Bottle.offset(CGPoint(x: -6, y: 7), angle: bottleAngle)
        drawArm(in: body, from: Self.rightShoulder, to: grip, bend: 0.2, inward: -1)
        Palette.bottle.draw(in: body, center: bottleCenter, angle: bottleAngle, level: waterLevel, time: time, ink: ink, capped: sip < 0.3)
        drawGlove(in: body, at: grip, angle: bottleAngle - 10, thumb: -1)

        let free = freeHand(motion: motion)
        drawArm(in: body, from: Self.leftShoulder, to: free.point, bend: free.bend, inward: 1)
        if free.thwip {
            drawThwip(in: body, at: free.point, angle: free.angle)
        } else {
            drawGlove(in: body, at: free.point, angle: free.angle, thumb: 1)
        }
    }

    /// A silky strand from the notch, glinting as it sways.
    private func drawWeb(in context: GraphicsContext, to end: CGPoint) {
        var strand = Path()
        strand.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        strand.addLine(to: end)
        context.stroke(strand, with: .color(Palette.ink.opacity(0.7)), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        context.stroke(strand, with: .color(Palette.silk), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        // A second, finer fibre twisting round the first.
        var twist = Path()
        twist.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        for y in stride(from: -6.0, through: end.y, by: 2) {
            twist.addLine(to: CGPoint(x: Self.ropeAnchor.x + 1.2 * sin(y / 3 + time * 2), y: y))
        }
        context.stroke(twist, with: .color(Palette.silk.opacity(0.75)), lineWidth: 0.7)
        let glint = (time * 0.5).truncatingRemainder(dividingBy: 1) * max(1, end.y)
        var spark = context
        spark.addFilter(.shadow(color: .white, radius: 2))
        spark.fill(Circle().path(in: CGRect(center: CGPoint(x: Self.ropeAnchor.x, y: glint), radius: 1.4)), with: .color(.white))
    }

    // MARK: Legs

    /// The web is tied round one ankle; the other leg hooks behind its knee.
    private func drawLegs(in context: GraphicsContext, motion: Motion) {
        // Hooked leg, drawn first so it tucks behind the straight one.
        let hip = CGPoint(x: 81, y: 80)
        let knee = hip + CGPoint(x: 20, y: -22).rotated(by: motion.kick)
        let foot = knee + (CGPoint(x: 74, y: 50) - CGPoint(x: 101, y: 58)).rotated(by: motion.kick * 1.4)
        let thigh = Sketch.limb(hip, (hip + knee) * 0.5, knee, 6.4, 5.6)
        let shin = Sketch.limb(knee, (knee + foot) * 0.5, foot, 5.6, 5)
        let toes = Sketch.limb(foot, foot + CGPoint(x: -2, y: -4), foot + CGPoint(x: -4, y: -9), 5, 4.2)
        drawLeg(in: context, parts: [thigh, shin], boot: shin.intersection(bootRegion(from: knee, to: foot, at: 0.42)).union(toes))

        let straightHip = CGPoint(x: 67, y: 80)
        let ankle = Self.ankle
        let leg = Sketch.limb(straightHip, CGPoint(x: 67.5, y: 56), ankle, 6.4, 5.2)
        let sole = Sketch.limb(ankle, ankle + CGPoint(x: -4, y: -5), ankle + CGPoint(x: -9, y: -10), 5.2, 4.4)
        drawLeg(in: context, parts: [leg], boot: leg.intersection(bootRegion(from: straightHip, to: ankle, at: 0.62)).union(sole))

        // Web wrapped round the ankle.
        for dy in [-5.0, 0.5] {
            let loop = Ellipse().path(in: CGRect(center: ankle + CGPoint(x: 0, y: dy), width: 15, height: 4.6))
            context.stroke(loop, with: .color(Palette.ink.opacity(0.75)), lineWidth: 2.8)
            context.stroke(loop, with: .color(Palette.silk), lineWidth: 1.3)
        }

        // Blue trunks and the red belt, over the tops of the legs.
        let trunks = Path(roundedRect: CGRect(x: 57, y: 72, width: 35, height: 18), cornerRadius: 8, style: .continuous)
        ink.paint(trunks, Palette.blue, in: context)
    }

    private func drawLeg(in context: GraphicsContext, parts: [Path], boot: Path) {
        ink.paint(parts.map { ($0, Palette.blue) }, in: context)
        ink.paint(boot, Palette.red, in: context)
        var web = context
        web.clip(to: boot)
        let bounds = boot.boundingRect
        for x in stride(from: bounds.minX + 3.5, to: bounds.maxX, by: 4.5) {
            var line = Path()
            line.move(to: CGPoint(x: x, y: bounds.minY))
            line.addLine(to: CGPoint(x: x + 2, y: bounds.maxY))
            web.stroke(line, with: .color(Palette.webLine), lineWidth: 0.6)
        }
    }

    /// The part of a leg past `fraction` of the way to the foot, with the
    /// boot's pointed cuff reaching back toward the knee.
    private func bootRegion(from start: CGPoint, to end: CGPoint, at fraction: CGFloat) -> Path {
        let along = (end - start).normalized
        let across = CGPoint(x: -along.y, y: along.x)
        let cuff = start + (end - start) * fraction
        var region = Path()
        region.move(to: cuff + across * 14)
        region.addLine(to: cuff - along * 4.5)
        region.addLine(to: cuff - across * 14)
        region.addLine(to: cuff - across * 14 + along * 50)
        region.addLine(to: cuff + across * 14 + along * 50)
        region.closeSubpath()
        return region
    }

    // MARK: Torso

    private static let torso = Sketch.rounded([
        CGPoint(x: 60, y: 86), CGPoint(x: 89, y: 86), CGPoint(x: 97, y: 118), CGPoint(x: 51, y: 118),
    ], radius: 7)

    /// Red chest panel, widening from the waist to the shoulders; blue down the flanks.
    private static let chest: Path = {
        var panel = Path()
        panel.move(to: CGPoint(x: 67, y: 84))
        panel.addLine(to: CGPoint(x: 82, y: 84))
        panel.addQuadCurve(to: CGPoint(x: 100, y: 112), control: CGPoint(x: 86, y: 104))
        panel.addLine(to: CGPoint(x: 100, y: 124))
        panel.addLine(to: CGPoint(x: 48, y: 124))
        panel.addLine(to: CGPoint(x: 48, y: 112))
        panel.addQuadCurve(to: CGPoint(x: 67, y: 84), control: CGPoint(x: 63, y: 104))
        panel.closeSubpath()
        return torso.intersection(panel)
    }()

    private func drawTorso(in context: GraphicsContext) {
        ink.paint(Self.torso, Palette.blue, in: context)
        let red = Self.chest
        ink.shade(red, Palette.red, in: context)
        ink.crease(red, in: context, width: 1, opacity: 0.8)

        // Web lines fanning out from the spider.
        let emblem = CGPoint(x: 74, y: 104)
        var web = context
        web.clip(to: red)
        for angle in stride(from: 0.0, to: 360, by: 36) {
            var spoke = Path()
            spoke.move(to: emblem)
            spoke.addLine(to: emblem + CGPoint(x: 34, y: 0).rotated(by: angle))
            web.stroke(spoke, with: .color(Palette.webLine), lineWidth: 0.6)
        }
        for radius in [10.0, 18] {
            var ring = Path()
            for step in 0...10 {
                let angle = Double(step) * 36
                let point = emblem + CGPoint(x: radius, y: 0).rotated(by: angle)
                if step == 0 { ring.move(to: point); continue }
                ring.addQuadCurve(to: point, control: emblem + CGPoint(x: radius * 0.86, y: 0).rotated(by: angle - 18))
            }
            web.stroke(ring, with: .color(Palette.webLine), lineWidth: 0.6)
        }
        drawSpiderEmblem(in: context, at: emblem)
        ink.gloss(CGRect(x: 58, y: 98, width: 7, height: 12), in: web, opacity: 0.22, angle: 10)
    }

    /// The black chest spider, upside down like its wearer.
    private func drawSpiderEmblem(in context: GraphicsContext, at center: CGPoint) {
        var spider = context
        spider.translateBy(x: center.x, y: center.y)
        spider.scaleBy(x: 1, y: -1)
        let legs: [[CGPoint]] = [
            [CGPoint(x: 1.4, y: -3.4), CGPoint(x: 5.2, y: -6.2), CGPoint(x: 6, y: -10.5)],
            [CGPoint(x: 1.8, y: -1.6), CGPoint(x: 6.4, y: -3), CGPoint(x: 8.4, y: -6.8)],
            [CGPoint(x: 1.8, y: 1.4), CGPoint(x: 6.4, y: 3.2), CGPoint(x: 8.2, y: 7.6)],
            [CGPoint(x: 1.4, y: 3.4), CGPoint(x: 4.8, y: 6.8), CGPoint(x: 5.2, y: 11)],
        ]
        for side in [-1.0, 1.0] {
            for leg in legs {
                var path = Path()
                path.move(to: CGPoint(x: leg[0].x * side, y: leg[0].y))
                path.addLine(to: CGPoint(x: leg[1].x * side, y: leg[1].y))
                path.addLine(to: CGPoint(x: leg[2].x * side, y: leg[2].y))
                spider.stroke(path, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
        spider.fill(Ellipse().path(in: CGRect(x: -2.4, y: -3.4, width: 4.8, height: 9.4)), with: .color(Palette.ink))
        spider.fill(Circle().path(in: CGRect(center: CGPoint(x: 0, y: -5.2), radius: 1.9)), with: .color(Palette.ink))
    }

    // MARK: Head (drawn upright around the origin; the caller flips it)

    private static let head: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -39))
        path.addCurve(to: CGPoint(x: 43, y: -4), control1: CGPoint(x: 25, y: -39), control2: CGPoint(x: 43, y: -25))
        path.addCurve(to: CGPoint(x: 0, y: 38), control1: CGPoint(x: 43, y: 19), control2: CGPoint(x: 23, y: 38))
        path.addCurve(to: CGPoint(x: -43, y: -4), control1: CGPoint(x: -23, y: 38), control2: CGPoint(x: -43, y: 19))
        path.addCurve(to: CGPoint(x: 0, y: -39), control1: CGPoint(x: -43, y: -25), control2: CGPoint(x: -25, y: -39))
        path.closeSubpath()
        return path
    }()

    private func drawHead(in context: GraphicsContext, ink: Ink) {
        let head = Self.head
        ink.paint(head, Palette.red, in: context)

        var mask = context
        mask.clip(to: head)
        drawMaskWeb(in: mask)
        // Lit from the world's top left, which is this frame's bottom right.
        ink.gloss(CGRect(x: 10, y: 20, width: 22, height: 9), in: mask, opacity: 0.28, angle: -30)

        if sip > 0.05 { drawChin(in: mask, ink: ink) }

        for side in [-1.0, 1.0] {
            drawLens(in: context, at: CGPoint(x: 19 * side, y: -3), side: side)
        }
    }

    /// Spokes from the bridge of the nose, joined by rings that sag toward it.
    private func drawMaskWeb(in context: GraphicsContext) {
        let hub = CGPoint(x: 0, y: 5)
        let shading = GraphicsContext.Shading.color(Palette.webLine)
        let spokes = stride(from: -90.0, to: 270, by: 30).map { $0 }
        for angle in spokes {
            var spoke = Path()
            spoke.move(to: hub)
            spoke.addLine(to: hub + CGPoint(x: 70, y: 0).rotated(by: angle))
            context.stroke(spoke, with: shading, lineWidth: 0.75)
        }
        for radius in [12.0, 23, 35, 48] {
            var ring = Path()
            for (index, angle) in (spokes + [spokes[0] + 360]).enumerated() {
                let point = hub + CGPoint(x: radius, y: 0).rotated(by: angle)
                guard index > 0 else { ring.move(to: point); continue }
                ring.addQuadCurve(to: point, control: hub + CGPoint(x: radius * 0.84, y: 0).rotated(by: angle - 15))
            }
            context.stroke(ring, with: shading, lineWidth: 0.75)
        }
    }

    /// Mask rolled up to the nose so he can drink, chin and mouth showing.
    private func drawChin(in context: GraphicsContext, ink: Ink) {
        let skin = Self.head.intersection(Path(CGRect(x: -50, y: 18, width: 100, height: 40)))
        ink.shade(skin, Palette.skin, in: context)
        let mouth = CGPoint(x: 0, y: 28)
        if sip > 0.6 {
            context.fill(Ellipse().path(in: CGRect(center: mouth, width: 6, height: 5)), with: .color(Palette.mouth))
        } else {
            var smile = Path()
            smile.move(to: mouth + CGPoint(x: -5, y: -1))
            smile.addQuadCurve(to: mouth + CGPoint(x: 5, y: -1), control: mouth + CGPoint(x: 0, y: 4))
            ink.crease(smile, in: context, width: 1.6, opacity: 0.9)
        }
        let roll = Path(roundedRect: CGRect(x: -45, y: 14, width: 90, height: 7.5), cornerRadius: 3.75)
        ink.paint(roll, Palette.red, in: context)
        for x in stride(from: -36.0, through: 36, by: 8) {
            var fold = Path()
            fold.move(to: CGPoint(x: x, y: 15))
            fold.addLine(to: CGPoint(x: x + 1.5, y: 20.5))
            ink.crease(fold, in: context, width: 0.7, opacity: 0.45)
        }
    }

    /// One of the big white lenses. Its shutters close from above and below
    /// to make the expression, like the lenses on the newer suits.
    private func drawLens(in context: GraphicsContext, at center: CGPoint, side: CGFloat) {
        let lids = Lids(mood: mood)
        var lens = context
        lens.translateBy(x: center.x, y: center.y)
        lens.scaleBy(x: side * lids.scale, y: lids.scale * (lids.blinks ? blink : 1))

        // Teardrop: broad at the outer top, tapering to a point by the nose.
        var shape = Path()
        shape.move(to: CGPoint(x: -12.5, y: 7))
        shape.addCurve(to: CGPoint(x: 9, y: -11.5), control1: CGPoint(x: -11, y: -4), control2: CGPoint(x: -2, y: -11.5))
        shape.addCurve(to: CGPoint(x: 13, y: 6.5), control1: CGPoint(x: 17.5, y: -11.5), control2: CGPoint(x: 18.5, y: 1.5))
        shape.addCurve(to: CGPoint(x: -12.5, y: 7), control1: CGPoint(x: 6, y: 11.5), control2: CGPoint(x: -4, y: 11))
        shape.closeSubpath()

        // The open part of the lens: below the upper shutter (a straight edge
        // through `top` at x = ∓14) and above the lower one (bowed by `arch`).
        let slope = (lids.top.outer - lids.top.inner) / 28
        var open = Path()
        open.move(to: CGPoint(x: -30, y: lids.top.inner - 16 * slope))
        open.addLine(to: CGPoint(x: 30, y: lids.top.outer + 16 * slope))
        open.addLine(to: CGPoint(x: 30, y: lids.bottom.outer))
        open.addLine(to: CGPoint(x: 17, y: lids.bottom.outer))
        open.addQuadCurve(
            to: CGPoint(x: -14, y: lids.bottom.inner),
            control: CGPoint(x: 1.5, y: (lids.bottom.inner + lids.bottom.outer) / 2 - lids.arch)
        )
        open.addLine(to: CGPoint(x: -30, y: lids.bottom.inner))
        open.closeSubpath()
        let visible = shape.intersection(open)

        lens.fill(visible, with: .linearGradient(
            Gradient(colors: [Palette.lens, Palette.lensShade]),
            startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 10)
        ))
        lens.stroke(visible, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.2 / lids.scale, lineJoin: .round))
    }

    /// Where the lens shutters sit, in lens space (y down, x toward the outer corner).
    private struct Lids {
        var top: (inner: CGFloat, outer: CGFloat) = (-40, -40)
        var bottom: (inner: CGFloat, outer: CGFloat) = (40, 40)
        /// How far the lower shutter bows up: a happy squint.
        var arch: CGFloat = 0
        var scale: CGFloat = 1
        var blinks = false

        init(mood: WaterBotMood) {
            switch mood {
            case .cheerful:
                blinks = true
            case .excited:
                scale = 1.14
            case .pleading:
                top = (-40, -5)
                scale = 1.08
                blinks = true
            case .thirsty:
                top = (-1, 1.5)
            case .delighted:
                bottom = (9, 6)
                arch = 13
            case .sleepy:
                top = (3, 3.5)
                bottom = (5.5, 6)
            case .tickled:
                top = (5, -9)
                bottom = (7, 10)
            }
        }
    }

    // MARK: Arms

    private func drawArm(in context: GraphicsContext, from shoulder: CGPoint, to hand: CGPoint, bend: CGFloat, inward: CGFloat) {
        let control = Sketch.elbow(shoulder, hand, bend: bend)
        let arm = Sketch.limb(shoulder, control, hand, 5.2, 4.3)
        ink.paint(arm, Palette.red, in: context)
        // Blue runs down the underside of the arm, toward the body.
        let underside = arm.subtracting(arm.offsetBy(dx: -3.6 * inward, dy: -1))
        ink.shade(underside, Palette.blue, in: context)
        ink.crease(underside, in: context, width: 0.8, opacity: 0.7)
    }

    private func drawGlove(in context: GraphicsContext, at point: CGPoint, angle: Double, thumb: CGFloat) {
        let hand = Sketch.mitten(at: point, radius: 5.8, angle: angle, thumb: thumb)
        ink.paint([(hand.thumb, Palette.red), (hand.palm, Palette.red)], in: context)
        var web = context
        web.clip(to: hand.palm)
        for offset in [-2.4, 2.4] {
            var line = Path()
            line.move(to: point + CGPoint(x: -8, y: offset).rotated(by: angle))
            line.addLine(to: point + CGPoint(x: 8, y: offset).rotated(by: angle))
            web.stroke(line, with: .color(Palette.webLine), lineWidth: 0.6)
        }
    }

    /// The web-shooter sign: middle and ring fingers folded, the rest out.
    private func drawThwip(in context: GraphicsContext, at point: CGPoint, angle: Double) {
        var hand = context
        hand.translateBy(x: point.x, y: point.y)
        hand.rotate(by: .degrees(angle))
        let local = ink.turned(by: angle)
        let palm = Ellipse().path(in: CGRect(x: -5.6, y: -5.4, width: 11.2, height: 10.8))
        let index = Sketch.limb(CGPoint(x: 2, y: -3.2), CGPoint(x: 6, y: -5), CGPoint(x: 10.5, y: -6.6), 1.9, 1.7)
        let pinky = Sketch.limb(CGPoint(x: 2, y: 3.2), CGPoint(x: 5.5, y: 4.8), CGPoint(x: 9, y: 6.4), 1.7, 1.5)
        let thumb = Sketch.limb(CGPoint(x: -1, y: -4), CGPoint(x: -1.5, y: -7.5), CGPoint(x: -0.5, y: -10.5), 2, 1.8)
        local.paint([(index, Palette.red), (pinky, Palette.red), (thumb, Palette.red), (palm, Palette.red)], in: hand)
        // Folded middle and ring fingers.
        for y in [-1.2, 1.4] {
            var knuckle = Path()
            knuckle.addArc(center: CGPoint(x: 3.2, y: y), radius: 1.7, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
            local.crease(knuckle, in: hand, width: 0.9, opacity: 0.7)
        }
        // The web-shooter button in the palm.
        hand.fill(Circle().path(in: CGRect(center: CGPoint(x: -1.2, y: 0), radius: 1.3)), with: .color(Palette.ink.opacity(0.75)))
    }

    /// The free hand: hanging loose, beckoning, or throwing the web-shooter sign.
    private func freeHand(motion: Motion) -> (point: CGPoint, angle: Double, bend: CGFloat, thwip: Bool) {
        let shoulder = Self.leftShoulder
        let t = time
        switch mood {
        case .cheerful:
            let reach = CGPoint(x: -21, y: 36).rotated(by: 8 * sin(t * 2.2))
            return (shoulder + reach, 115 + 8 * sin(t * 2.2), -0.18, false)
        case .excited:
            return (shoulder + CGPoint(x: -32, y: 16 + 2 * sin(t * 7)), 165, 0.12, true)
        case .pleading:
            return (shoulder + CGPoint(x: -24, y: 32).rotated(by: 6 * sin(t * 3)), 105, -0.16, false)
        case .thirsty:
            return (shoulder + CGPoint(x: -19, y: 40), 100, -0.1, false)
        case .delighted:
            return (shoulder + CGPoint(x: -31, y: 20).rotated(by: 6 * sin(t * 6)), 160, 0.12, true)
        case .sleepy:
            return (shoulder + CGPoint(x: -17, y: 41), 98, -0.08, false)
        case .tickled:
            let reach = CGPoint(x: -30, y: 22).rotated(by: 22 * sin(t * 14))
            return (shoulder + reach, 150 + 22 * sin(t * 14), 0.1, false)
        }
    }

    /// Sweat when thirsty, floating z's when sleepy (in world space, so they rise).
    private func drawMoodExtras(in context: GraphicsContext) {
        let head = Self.headCenter
        switch mood {
        case .thirsty:
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: head.x - 44, y: head.y - 4 + drip * 12)
            let drop = DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11))
            var sweat = context
            sweat.opacity = 1 - drip * 0.6
            sweat.stroke(drop, with: .color(Palette.ink), lineWidth: 2)
            sweat.fill(drop, with: .color(Bottle.water))
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: head.x - 50 - phase * 12, y: head.y + 4 - phase * 30)
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
    private func bottlePose(wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let angle = 12 + (-70 - 12) * Double(eased) + wiggle
        let rest = CGPoint(x: 133, y: 158)
        let drinking = Self.mouth - Bottle.offset(Bottle.neck, angle: -70)
        return (rest + (drinking - rest) * eased, angle)
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
        /// The hooked leg's swing, in degrees.
        var kick = 0.0
        var wiggle = 0.0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 4 * sin(t * 1.6)
                headTilt = 4 * sin(t * 1.3 + 0.5)
                kick = 8 * sin(t * 2.4)
            case .excited:
                swing = 2 * sin(t * 2)
                lift = -3 * abs(sin(t * 6))
                headTilt = 5 * sin(t * 3)
                kick = 14 * sin(t * 7)
            case .pleading:
                swing = 3 * sin(t * 1.5)
                headTilt = 9 + 2 * sin(t * 1.2)
                kick = 4 * sin(t * 2)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 2
                headTilt = -8 + 1.5 * sin(t * 0.8)
                kick = -6 + 2 * sin(t * 0.9)
            case .delighted:
                swing = 6 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                headTilt = 5 * sin(t * 3)
                kick = 12 * sin(t * 6)
            case .sleepy:
                swing = 1.5 * sin(t * 0.7)
                headTilt = -10 + 3 * sin(t * 0.9)
                kick = -8 + 2 * sin(t * 0.7)
            case .tickled:
                swing = 7 * sin(t * 26)
                lift = -3
                headTilt = 10 * sin(t * 18)
                kick = 18 * sin(t * 12)
            }
            // Bungee: Spidey drops in on the web and bobs until the strand settles.
            lift += CGFloat(10 * exp(-2.6 * t) * sin(t * 10))
        }
    }

    enum Palette {
        static let ink = Color(hex: 0x1C070B)
        static let inkStyle = Ink(color: ink)
        static let red = Tone(0xD8262F, shade: 0x9C1420, light: 0xFF6A63)
        static let blue = Tone(0x2559CC, shade: 0x163A8E, light: 0x5E8EF2)
        static let skin = Tone(0xF2C4A0, shade: 0xD69B78, light: 0xFFE2CB)
        static let webLine = Color(hex: 0x4A0910).opacity(0.62)
        static let lens = Color.white
        static let lensShade = Color(hex: 0xCBD7E8)
        static let mouth = Color(hex: 0x5A1E1E)
        static let silk = Color(hex: 0xF3F5FA)
        static let bottle = Bottle(cap: blue, label: Color(hex: 0x2559CC))
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
