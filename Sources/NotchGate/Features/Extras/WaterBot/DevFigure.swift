import SwiftUI

/// The water bot's most relatable stand-in, drawn in code: a tired developer
/// in a hoodie, dangling from the notch by the coiled cable of his headphones
/// as if the notch were an audio jack. One hand holds his open laptop up so
/// you can see the screen, and the screen shows how he's doing: code typing
/// itself, a progress bar stuck at 99%, a 404, a 200 OK. The other hand holds
/// the bottle. Like `WaterBotFigure`, everything is a function of `mood` and `time`.
struct DevFigure: View {
    var mood: WaterBotMood
    /// Seconds since he appeared; drives the idle motion.
    var time: TimeInterval
    /// 0 = bottle at his side, 1 = tipped to the mouth.
    var sip: CGFloat = 0
    /// How full the bottle is, 0…1.
    var waterLevel: CGFloat = 0.8

    static let size = WaterBotFigure.size
    /// Where the headphone cable leaves the top edge; he swings around it.
    static let ropeAnchor = CGPoint(x: 86, y: 0)
    /// Where the bottle meets the mouth, for the splash when you drink.
    static let mouth = CGPoint(x: 86, y: 103)

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

    private static let headCenter = CGPoint(x: 86, y: 86)
    private static let neck = CGPoint(x: 86, y: 116)
    /// Where the cable plugs into the top of the headphones, relative to the head.
    private static let jack = CGPoint(x: 0, y: -49)
    private static let leftShoulder = CGPoint(x: 68, y: 121)
    private static let rightShoulder = CGPoint(x: 104, y: 121)
    /// The hand under the laptop's front edge; the laptop pivots around it.
    private static let laptopGrip = CGPoint(x: 42, y: 160)

    private var ink: Ink { Palette.inkStyle }

    private func draw(in context: GraphicsContext, motion: Motion) {
        var body = context
        body.translateBy(x: 0, y: motion.lift)

        // The head tilts around the neck, so the jack (and the cable's end) moves with it.
        let jack = Self.neck + (Self.headCenter + Self.jack - Self.neck).rotated(by: motion.headTilt)
        drawCable(in: context, to: jack + CGPoint(x: 0, y: motion.lift))

        drawHood(in: body)
        drawLegs(in: body, motion: motion)
        drawTorso(in: body, motion: motion)

        var head = body
        head.translateBy(x: Self.neck.x, y: Self.neck.y)
        head.rotate(by: .degrees(motion.headTilt))
        head.translateBy(x: Self.headCenter.x - Self.neck.x, y: Self.headCenter.y - Self.neck.y)
        drawHead(in: head, ink: ink.turned(by: motion.headTilt), motion: motion)
        drawMoodExtras(in: body)

        let (bottleCenter, bottleAngle) = bottlePose(wiggle: motion.wiggle)
        let grip = bottleCenter + Bottle.offset(CGPoint(x: -6, y: 7), angle: bottleAngle)
        drawArm(in: body, from: Self.rightShoulder, to: grip, bend: -0.2)
        Palette.bottle.draw(in: body, center: bottleCenter, angle: bottleAngle, level: waterLevel, time: time, ink: ink, capped: sip < 0.3)
        drawHand(in: body, at: grip, angle: bottleAngle - 10, thumb: -1, ink: ink)

        drawArm(in: body, from: Self.leftShoulder, to: Self.laptopGrip, bend: -0.12)
        var laptop = body
        laptop.translateBy(x: Self.laptopGrip.x, y: Self.laptopGrip.y)
        laptop.rotate(by: .degrees(motion.laptopTilt))
        drawLaptop(in: laptop, ink: ink.turned(by: motion.laptopTilt))
    }

    /// The coiled headphone cable, from the notch down to the jack. The coils
    /// stretch and bunch as he bounces on it.
    private func drawCable(in context: GraphicsContext, to end: CGPoint) {
        let start = CGPoint(x: Self.ropeAnchor.x, y: -6)
        let span = end - start
        let along = span.normalized
        let across = CGPoint(x: -along.y, y: along.x)
        var cable = Path()
        cable.move(to: start)
        let steps = 160
        for step in 1...steps {
            let s = CGFloat(step) / CGFloat(steps)
            // Straight where it leaves the notch and where it plugs in, coiled between.
            let coil = min(1, max(0, (s - 0.1) / 0.78))
            let envelope = min(1, coil * 8, (1 - coil) * 8)
            let angle = Double(coil) * 7 * 2 * .pi
            let loop = across * (3.2 * sin(angle)) + along * (1.7 * (1 - cos(angle)))
            cable.addLine(to: start + span * s + loop * envelope)
        }
        let style = StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
        context.stroke(cable, with: .color(Palette.ink), style: style)
        context.stroke(cable, with: .color(Palette.clay.base), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: Body

    /// The hood, bunched up behind his neck.
    private func drawHood(in context: GraphicsContext) {
        let hood = Ellipse().path(in: CGRect(center: CGPoint(x: 86, y: 116), width: 58, height: 20))
        ink.paint(hood, Palette.hoodieDeep, in: context)
    }

    private func drawLegs(in context: GraphicsContext, motion: Motion) {
        for (hip, angle) in [(CGPoint(x: 79, y: 150), motion.legLeft), (CGPoint(x: 93, y: 150), motion.legRight)] {
            let foot = hip + CGPoint(x: 0, y: 27).rotated(by: angle)
            let leg = Sketch.limb(hip, (hip + foot) * 0.5, foot, 6.4, 5.6)
            let cuff = leg.intersection(cuffRegion(from: hip, to: foot, at: 0.78))
            let shoe = Sketch.limb(
                foot + CGPoint(x: -1, y: 0).rotated(by: angle),
                foot + CGPoint(x: 1, y: 3.5).rotated(by: angle),
                foot + CGPoint(x: 4.5, y: 5).rotated(by: angle),
                6, 4.8
            )
            let sole = shoe.intersection(cuffRegion(from: foot, to: foot + CGPoint(x: 0, y: 10).rotated(by: angle), at: 0.62))
            ink.paint(leg, Palette.pants, in: context)
            ink.shade(cuff, Palette.pantsCuff, in: context)
            ink.crease(cuff, in: context, width: 0.9, opacity: 0.5)
            ink.paint(shoe, Palette.sneaker, in: context)
            ink.shade(sole, Palette.clay, in: context)
        }
    }

    /// The part of a limb past `fraction` of the way to its end (cuffs, soles).
    private func cuffRegion(from start: CGPoint, to end: CGPoint, at fraction: CGFloat) -> Path {
        let along = (end - start).normalized
        let across = CGPoint(x: -along.y, y: along.x)
        let cuff = start + (end - start) * fraction
        var region = Path()
        region.move(to: cuff + across * 14)
        region.addLine(to: cuff - across * 14)
        region.addLine(to: cuff - across * 14 + along * 60)
        region.addLine(to: cuff + across * 14 + along * 60)
        region.closeSubpath()
        return region
    }

    private static let torso = Sketch.rounded([
        CGPoint(x: 67, y: 112), CGPoint(x: 105, y: 112), CGPoint(x: 110, y: 157), CGPoint(x: 62, y: 157),
    ], radius: 9)

    /// A comfy hoodie: ribbed hem, a `</>` on the chest, drawstrings that swing.
    private func drawTorso(in context: GraphicsContext, motion: Motion) {
        let torso = Self.torso
        ink.paint(torso, Palette.hoodie, in: context)

        var cloth = context
        cloth.clip(to: torso)
        let hem = Path(CGRect(x: 58, y: 150, width: 56, height: 9))
        ink.shade(hem, Palette.hoodieDeep, in: cloth)
        var seam = Path()
        seam.move(to: CGPoint(x: 58, y: 150))
        seam.addLine(to: CGPoint(x: 114, y: 150))
        ink.crease(seam, in: cloth, width: 1, opacity: 0.6)
        for x in stride(from: 66.0, through: 106, by: 4) {
            var rib = Path()
            rib.move(to: CGPoint(x: x, y: 152))
            rib.addLine(to: CGPoint(x: x, y: 156))
            ink.crease(rib, in: cloth, width: 0.7, opacity: 0.25)
        }
        cloth.draw(
            Text("</>").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(Palette.print),
            at: CGPoint(x: 86, y: 140)
        )
        ink.gloss(CGRect(x: 71, y: 116, width: 10, height: 6), in: cloth, opacity: 0.2, angle: -15)

        // Drawstrings, lagging behind the swing.
        let sway = -motion.swing * 0.6
        for x in [80.0, 92.0] {
            let end = CGPoint(x: x + sway + (x < 86 ? -0.8 : 0.8), y: 131)
            var string = Path()
            string.move(to: CGPoint(x: x, y: 116))
            string.addQuadCurve(to: end, control: CGPoint(x: x, y: 125))
            context.stroke(string, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            context.stroke(string, with: .color(Palette.string), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            let aglet = Path(roundedRect: CGRect(center: end + CGPoint(x: 0, y: 1.5), width: 2.8, height: 4.4), cornerRadius: 1.2)
            ink.paint(aglet, Palette.clay, in: context)
        }
    }

    // MARK: Head (drawn around the origin; the caller places and tilts it)

    private static let skull: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -33))
        path.addCurve(to: CGPoint(x: 34, y: -1), control1: CGPoint(x: 22, y: -33), control2: CGPoint(x: 34, y: -20))
        path.addCurve(to: CGPoint(x: 0, y: 31), control1: CGPoint(x: 34, y: 18), control2: CGPoint(x: 20, y: 31))
        path.addCurve(to: CGPoint(x: -34, y: -1), control1: CGPoint(x: -20, y: 31), control2: CGPoint(x: -34, y: 18))
        path.addCurve(to: CGPoint(x: 0, y: -33), control1: CGPoint(x: -34, y: -20), control2: CGPoint(x: -22, y: -33))
        path.closeSubpath()
        return path
    }()

    /// Messy hair: a tousled crown, and a fringe flopping over the forehead.
    private static let hair: Path = {
        var points: [CGPoint] = []
        // The crown, left to right over the top; every few points a tuft sticks out.
        let tufts: [Int: CGFloat] = [2: 5, 5: 6, 8: 4, 12: 6, 15: 5, 18: 4]
        for step in 0...20 {
            let angle = (170 + Double(step) * 10) * .pi / 180
            let reach = 1 + (tufts[step] ?? 0) / 38
            points.append(CGPoint(x: 38 * cos(angle) * reach, y: 1 + 40 * sin(angle) * reach))
        }
        // The fringe, right to left: tips flopping down between the roots.
        points += [
            CGPoint(x: 33, y: 3), CGPoint(x: 28, y: -15), CGPoint(x: 23, y: -8), CGPoint(x: 17, y: -18),
            CGPoint(x: 11, y: -9), CGPoint(x: 5, y: -19), CGPoint(x: -1, y: -10), CGPoint(x: -7, y: -19),
            CGPoint(x: -13, y: -9), CGPoint(x: -19, y: -17), CGPoint(x: -25, y: -7), CGPoint(x: -29, y: -14),
            CGPoint(x: -33, y: 3),
        ]
        return Sketch.rounded(points, radius: 2.6)
    }()

    private func drawHead(in context: GraphicsContext, ink: Ink, motion: Motion) {
        let skull = Self.skull
        ink.paint(skull, Palette.skin, in: context)
        // The screen lights his face from below, on the laptop's side.
        var face = context
        face.clip(to: skull)
        face.fill(skull, with: .radialGradient(
            Gradient(colors: [glow.opacity(0.3 * glowStrength), glow.opacity(0)]),
            center: CGPoint(x: -42, y: 44), startRadius: 0, endRadius: 62
        ))

        drawFace(in: context, ink: ink)
        drawCowlick(in: context, ink: ink, lean: motion.cowlick)
        ink.paint(Self.hair, Palette.hair, in: context)
        var hair = context
        hair.clip(to: Self.hair)
        ink.gloss(CGRect(x: -24, y: -34, width: 16, height: 6), in: hair, opacity: 0.18, angle: -28)
        drawGlasses(in: context, drop: motion.glassesDrop)
        drawHeadphones(in: context, ink: ink)
        if mood == .sleepy { drawNoseBubble(in: context) }
    }

    /// The strand of hair that never lies flat: perky when he's up, drooping when he's not.
    private func drawCowlick(in context: GraphicsContext, ink: Ink, lean: Double) {
        let root = CGPoint(x: -9, y: -35)
        let control = root + CGPoint(x: -7, y: -11).rotated(by: lean)
        let tip = root + CGPoint(x: 2, y: -18).rotated(by: lean)
        ink.paint(Sketch.limb(root, control, tip, 3, 0.9), Palette.hair, in: context)
    }

    private static let lensCenter = CGPoint(x: 14, y: 0)
    private static let lensRadius: CGFloat = 10

    private func drawFace(in context: GraphicsContext, ink: Ink) {
        if [.delighted, .tickled, .excited].contains(mood) {
            for side in [-1.0, 1.0] {
                context.fill(Ellipse().path(in: CGRect(center: CGPoint(x: 21 * side, y: 13), width: 8, height: 4)),
                             with: .color(Palette.blush.opacity(0.7)))
            }
        }
        for side in [-1.0, 1.0] {
            drawEye(in: context, side: side)
        }
        var nose = Path()
        nose.move(to: CGPoint(x: 0.4, y: 6.4))
        nose.addQuadCurve(to: CGPoint(x: 0.6, y: 9.4), control: CGPoint(x: 2.6, y: 8.4))
        ink.crease(nose, in: context, width: 1.2, opacity: 0.5)
        drawMouth(in: context, at: CGPoint(x: 0, y: 17), ink: ink)
    }

    /// Drawn for the right eye and mirrored for the left. The bags under them never quite go away.
    private func drawEye(in context: GraphicsContext, side: CGFloat) {
        var eye = context
        eye.translateBy(x: Self.lensCenter.x * side, y: Self.lensCenter.y)
        eye.scaleBy(x: side, y: 1)
        let line = GraphicsContext.Shading.color(Palette.ink)
        let round = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)

        switch mood {
        case .cheerful:
            drawPupil(in: eye, width: 6.4, height: 7.4, shine: 1.3, lid: blink == 1 ? 0.45 : 1)
            drawBag(in: eye, opacity: 0.9)
        case .excited:
            drawPupil(in: eye, width: 7.6, height: 9, shine: 2.2, lid: blink == 1 ? 0 : 1)
            drawBag(in: eye, opacity: 0.5)
        case .pleading:
            drawPupil(in: eye, width: 8.6, height: 10, shine: 2.6, lid: 0)
            // A watery glint along the bottom.
            var tear = Path()
            tear.move(to: CGPoint(x: -3.4, y: 4.4))
            tear.addQuadCurve(to: CGPoint(x: 3.4, y: 4.4), control: CGPoint(x: 0, y: 6 + 0.5 * sin(time * 8)))
            eye.stroke(tear, with: .color(Bottle.water), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            drawBag(in: eye, opacity: 0.8)
        case .thirsty:
            // Dizzy spirals: his brain is buffering.
            var spiral = Path()
            for step in 0...40 {
                let progress = Double(step) / 40
                let angle = progress * 2.3 * 2 * .pi + time * 5
                let radius = 0.5 + 5 * progress
                let point = CGPoint(x: radius * cos(angle), y: 0.6 + radius * sin(angle))
                if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
            }
            eye.stroke(spiral, with: line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            drawBag(in: eye, opacity: 0.9)
        case .delighted:
            var arc = Path()
            arc.move(to: CGPoint(x: -5, y: 2))
            arc.addQuadCurve(to: CGPoint(x: 5, y: 2), control: CGPoint(x: 0, y: -6))
            eye.stroke(arc, with: line, style: round)
        case .sleepy:
            var shut = Path()
            shut.move(to: CGPoint(x: -5, y: 0.5))
            shut.addQuadCurve(to: CGPoint(x: 5, y: 0.5), control: CGPoint(x: 0, y: 4))
            eye.stroke(shut, with: line, style: round)
            drawBag(in: eye, opacity: 0.9)
        case .tickled:
            var chevron = Path()
            chevron.move(to: CGPoint(x: 4.5, y: -4))
            chevron.addLine(to: CGPoint(x: -3.5, y: 0))
            chevron.addLine(to: CGPoint(x: 4.5, y: 4))
            eye.stroke(chevron, with: line, style: round)
        }
    }

    /// A dark pupil with catch-lights. `lid` is how far the upper lid has come
    /// down over it: 0 wide awake, 1 shut.
    private func drawPupil(in eye: GraphicsContext, width: CGFloat, height: CGFloat, shine: CGFloat, lid: CGFloat) {
        let rect = CGRect(center: CGPoint(x: 0, y: 0.8), width: width, height: height)
        let lidY = rect.minY - 0.6 + (rect.height + 0.6) * lid
        var lidLine = Path()
        lidLine.move(to: CGPoint(x: -9, y: lidY))
        lidLine.addQuadCurve(to: CGPoint(x: 9, y: lidY + 1.2), control: CGPoint(x: 0, y: lidY + 2.4))
        var open = eye
        if lid > 0 {
            var below = lidLine
            below.addLine(to: CGPoint(x: 9, y: 12))
            below.addLine(to: CGPoint(x: -9, y: 12))
            below.closeSubpath()
            open.clip(to: below)
        }
        open.fill(Ellipse().path(in: rect), with: .color(Palette.pupil))
        open.fill(Circle().path(in: CGRect(center: CGPoint(x: rect.midX - width * 0.18, y: rect.midY - height * (lid > 0 ? -0.02 : 0.18)), radius: shine)),
                  with: .color(.white))
        open.fill(Circle().path(in: CGRect(center: CGPoint(x: rect.midX + width * 0.2, y: rect.midY + height * 0.24), radius: shine * 0.5)),
                  with: .color(.white.opacity(0.85)))
        guard lid > 0 else { return }
        var edge = eye
        edge.clip(to: Path(CGRect(x: -width / 2 - 1.6, y: -12, width: width + 3.2, height: 24)))
        edge.stroke(lidLine, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
    }

    private func drawBag(in eye: GraphicsContext, opacity: Double) {
        var bag = Path()
        bag.move(to: CGPoint(x: -4.6, y: 6.4))
        bag.addQuadCurve(to: CGPoint(x: 4.6, y: 6), control: CGPoint(x: -0.2, y: 9))
        eye.stroke(bag, with: .color(Palette.eyeBag.opacity(opacity)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private func drawMouth(in context: GraphicsContext, at mouth: CGPoint, ink: Ink) {
        switch mood {
        case .cheerful:
            // A tired little smile: trying his best.
            var smile = Path()
            smile.move(to: mouth + CGPoint(x: -4, y: 0))
            smile.addQuadCurve(to: mouth + CGPoint(x: 4, y: -0.6), control: mouth + CGPoint(x: 0.4, y: 3))
            ink.crease(smile, in: context, width: 1.6, opacity: 0.95)
        case .excited, .delighted, .tickled:
            if mood == .delighted && sip > 0.6 {
                context.fill(Ellipse().path(in: CGRect(center: mouth, width: 6, height: 5)), with: .color(Palette.mouth))
                return
            }
            let width: CGFloat = mood == .tickled ? 7 : 6
            var grin = Path()
            grin.move(to: mouth + CGPoint(x: -width, y: -2))
            grin.addQuadCurve(to: mouth + CGPoint(x: width, y: -2), control: mouth + CGPoint(x: 0, y: -3))
            grin.addQuadCurve(to: mouth + CGPoint(x: -width, y: -2),
                              control: mouth + CGPoint(x: 0, y: 9 + (mood == .tickled ? 1.5 * sin(time * 20) : 0)))
            grin.closeSubpath()
            context.fill(grin, with: .color(Palette.mouth))
            var tongue = context
            tongue.clip(to: grin)
            tongue.fill(Ellipse().path(in: CGRect(center: mouth + CGPoint(x: 0, y: 4.4), width: width * 1.1, height: 4)), with: .color(Palette.tongue))
            ink.crease(grin, in: context, width: 1.2, opacity: 0.95)
        case .pleading:
            var pout = Path()
            pout.move(to: mouth + CGPoint(x: -3.5, y: 1.2))
            pout.addQuadCurve(to: mouth + CGPoint(x: 3.5, y: 1.2), control: mouth + CGPoint(x: 0, y: -2.4 + 0.6 * sin(time * 9)))
            ink.crease(pout, in: context, width: 1.6, opacity: 0.95)
        case .thirsty:
            // Parched: mouth open, tongue out, panting.
            let open = Ellipse().path(in: CGRect(center: mouth + CGPoint(x: 0, y: 0.5), width: 8, height: 5.5))
            context.fill(open, with: .color(Palette.mouth))
            ink.crease(open, in: context, width: 1.2, opacity: 0.95)
            let pant = 1.2 * sin(time * 7)
            let tongue = Path(roundedRect: CGRect(x: mouth.x - 2.4, y: mouth.y + 0.5, width: 4.8, height: 6.5 + pant), cornerRadius: 2.4)
            ink.paint(tongue, Palette.tongueTone, in: context)
        case .sleepy:
            let snore = 2.6 + 1.2 * sin(time * 2)
            context.fill(Ellipse().path(in: CGRect(center: mouth, width: snore, height: snore)), with: .color(Palette.mouth))
        }
    }

    /// Big round glasses, tinted by the glow of whatever's on screen.
    private func drawGlasses(in context: GraphicsContext, drop: CGFloat) {
        var glasses = context
        glasses.translateBy(x: 0, y: drop)
        let frame = GraphicsContext.Shading.color(Palette.frame)
        let rim = StrokeStyle(lineWidth: 2.4, lineCap: .round)
        for side in [-1.0, 1.0] {
            let center = CGPoint(x: Self.lensCenter.x * side, y: Self.lensCenter.y)
            let lens = Circle().path(in: CGRect(center: center, radius: Self.lensRadius))
            glasses.fill(lens, with: .color(glow.opacity(0.12 * glowStrength)))
            var glass = glasses
            glass.clip(to: lens)
            let glare = Capsule().path(in: CGRect(x: -1.6, y: -7, width: 3.2, height: 14))
                .rotated(by: 35, around: .zero)
                .offsetBy(dx: center.x - 4, dy: center.y - 1)
            glass.fill(glare, with: .color(.white.opacity(0.35)))
            glass.fill(Circle().path(in: CGRect(center: center + CGPoint(x: 5, y: -5), radius: 1.2)), with: .color(.white.opacity(0.6)))

            var temple = Path()
            temple.move(to: CGPoint(x: (Self.lensCenter.x + Self.lensRadius) * side, y: -1.5))
            temple.addLine(to: CGPoint(x: 32 * side, y: -3))
            glasses.stroke(temple, with: frame, style: rim)
            glasses.stroke(lens, with: frame, style: rim)
        }
        var bridge = Path()
        bridge.move(to: CGPoint(x: -Self.lensCenter.x + Self.lensRadius, y: -1))
        bridge.addQuadCurve(to: CGPoint(x: Self.lensCenter.x - Self.lensRadius, y: -1), control: CGPoint(x: 0, y: -4))
        glasses.stroke(bridge, with: frame, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Over-ear headphones, with the cable from the notch plugged in at the top.
    private func drawHeadphones(in context: GraphicsContext, ink: Ink) {
        let band = Sketch.limb(CGPoint(x: -37, y: -2), CGPoint(x: 0, y: -82), CGPoint(x: 37, y: -2), 3.2, 3.2)
        ink.paint(band, Palette.band, in: context)
        for side in [-1.0, 1.0] {
            let cup = Path(roundedRect: CGRect(center: CGPoint(x: 37 * side, y: 4), width: 13, height: 25), cornerRadius: 5.5)
            ink.paint(cup, Palette.clay, in: context)
            let plate = Ellipse().path(in: CGRect(center: CGPoint(x: 38.5 * side, y: 4), width: 6.5, height: 15))
            ink.crease(plate, in: context, width: 1, opacity: 0.45)
        }
        let housing = Path(roundedRect: CGRect(center: CGPoint(x: 0, y: -44.5), width: 9, height: 7), cornerRadius: 2.2)
        let collar = Path(roundedRect: CGRect(center: CGPoint(x: 0, y: -48.6), width: 5, height: 2.8), cornerRadius: 1)
        ink.paint([(housing, Palette.band), (collar, Palette.clay)], in: context)
    }

    /// Asleep, a bubble grows and shrinks at his nose with every breath.
    private func drawNoseBubble(in context: GraphicsContext) {
        let breath = 0.5 + 0.5 * sin(time * 1.4)
        let radius = 1.5 + 4.5 * breath
        let center = CGPoint(x: 2.5 + radius * 0.8, y: 9 + radius * 0.3)
        let bubble = Circle().path(in: CGRect(center: center, radius: radius))
        context.fill(bubble, with: .color(Bottle.water.opacity(0.35)))
        context.stroke(bubble, with: .color(.white.opacity(0.85)), lineWidth: 1)
        context.fill(Circle().path(in: CGRect(center: center + CGPoint(x: -radius * 0.4, y: -radius * 0.4), radius: radius * 0.22)),
                     with: .color(.white.opacity(0.9)))
    }

    /// A battery over his head (nearly flat when he's thirsty, charging while
    /// he drinks), sweat, and floating z's.
    private func drawMoodExtras(in context: GraphicsContext) {
        let head = Self.headCenter
        switch mood {
        case .thirsty:
            let blink = time.truncatingRemainder(dividingBy: 1) < 0.6
            drawBattery(in: context, at: CGPoint(x: head.x + 37, y: head.y - 40), bars: blink ? 1 : 0, color: Palette.error, bolt: false)
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: head.x - 40, y: head.y - 26 + drip * 12)
            let drop = DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11))
            var sweat = context
            sweat.opacity = 1 - drip * 0.6
            sweat.stroke(drop, with: .color(Palette.ink), lineWidth: 2)
            sweat.fill(drop, with: .color(Bottle.water))
        case .delighted:
            let bars = 1 + Int(time * 3) % 4
            drawBattery(in: context, at: CGPoint(x: head.x + 37, y: head.y - 40), bars: bars, color: Palette.success, bolt: true)
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: head.x + 40 + phase * 14, y: head.y - 30 - phase * 24)
                var snore = context
                snore.opacity = sin(phase * .pi)
                snore.draw(
                    Text("z").font(.system(size: 9 + phase * 6, weight: .heavy, design: .rounded)).foregroundColor(.white),
                    at: point
                )
            }
        default:
            break
        }
    }

    private func drawBattery(in context: GraphicsContext, at center: CGPoint, bars: Int, color: Color, bolt: Bool) {
        let shell = Path(roundedRect: CGRect(center: center, width: 18, height: 10), cornerRadius: 2.6)
        let nub = Path(roundedRect: CGRect(x: center.x + 8.6, y: center.y - 2.2, width: 2.6, height: 4.4), cornerRadius: 1)
        for part in [shell, nub] {
            context.stroke(part, with: .color(Palette.ink), lineWidth: 3.8)
        }
        context.fill(shell, with: .color(Palette.bezel))
        context.fill(nub, with: .color(.white))
        context.stroke(shell, with: .color(.white), lineWidth: 1.4)
        for bar in 0..<bars {
            let rect = CGRect(x: center.x - 6.6 + Double(bar) * 3.4, y: center.y - 2.8, width: 2.6, height: 5.6)
            context.fill(Path(roundedRect: rect, cornerRadius: 0.6), with: .color(color))
        }
        guard bolt else { return }
        var flash = Path()
        flash.move(to: center + CGPoint(x: 1.6, y: -6.5))
        flash.addLine(to: center + CGPoint(x: -2.6, y: 0.6))
        flash.addLine(to: center + CGPoint(x: 0, y: 0.6))
        flash.addLine(to: center + CGPoint(x: -1.6, y: 6.5))
        flash.addLine(to: center + CGPoint(x: 2.6, y: -0.6))
        flash.addLine(to: center + CGPoint(x: 0, y: -0.6))
        flash.closeSubpath()
        context.stroke(flash, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        context.fill(flash, with: .color(Color(hex: 0xFFD84D)))
    }

    // MARK: Arms

    /// A hoodie sleeve with a ribbed cuff at the wrist.
    private func drawArm(in context: GraphicsContext, from shoulder: CGPoint, to hand: CGPoint, bend: CGFloat) {
        let control = Sketch.elbow(shoulder, hand, bend: bend)
        let sleeve = Sketch.limb(shoulder, control, hand, 6, 5.2)
        let wrist = Sketch.quad(shoulder, control, hand, 0.74)
        let cuff = sleeve.intersection(cuffRegion(from: wrist, to: hand, at: 0))
        ink.paint(sleeve, Palette.hoodie, in: context)
        ink.shade(cuff, Palette.hoodieDeep, in: context)
        ink.crease(cuff, in: context, width: 0.9, opacity: 0.5)
    }

    private func drawHand(in context: GraphicsContext, at point: CGPoint, angle: Double, thumb: CGFloat, ink: Ink) {
        let hand = Sketch.mitten(at: point, radius: 5.6, angle: angle, thumb: thumb)
        ink.paint([(hand.thumb, Palette.skin), (hand.palm, Palette.skin)], in: context)
    }

    // MARK: Laptop (drawn around the hand holding its front edge)

    private func drawLaptop(in context: GraphicsContext, ink: Ink) {
        // The screen's glow spills out around it, fading out before the edge of the canvas.
        var halo = context
        halo.scaleBy(x: 0.85, y: 1)
        halo.fill(
            Circle().path(in: CGRect(center: CGPoint(x: 0, y: -28), radius: 40)),
            with: .radialGradient(
                Gradient(colors: [glow.opacity(0.32 * glowStrength), glow.opacity(0)]),
                center: CGPoint(x: 0, y: -28), startRadius: 8, endRadius: 40
            )
        )
        let lid = Path(roundedRect: CGRect(x: -24, y: -47, width: 48, height: 38), cornerRadius: 4.5)
        let deck = Sketch.rounded([
            CGPoint(x: -24, y: -9.5), CGPoint(x: 24, y: -9.5), CGPoint(x: 29, y: -1.5), CGPoint(x: -29, y: -1.5),
        ], radius: 1.6)
        let lip = Path(roundedRect: CGRect(x: -29, y: -2, width: 58, height: 3.6), cornerRadius: 1.6)
        ink.paint([(lid, Palette.silver), (deck, Palette.silver), (lip, Palette.silverEdge)], in: context)

        context.fill(Path(roundedRect: CGRect(x: -22.4, y: -45.4, width: 44.8, height: 34.8), cornerRadius: 3.2),
                     with: .color(Palette.bezel))
        let display = CGRect(x: -20.6, y: -43.4, width: 41.2, height: 31.4)
        drawScreen(in: context, rect: display)
        // It has a notch too.
        context.fill(Path(roundedRect: CGRect(x: -3.6, y: display.minY - 0.6, width: 7.2, height: 2.6), cornerRadius: 1.2),
                     with: .color(Palette.bezel))

        var keyboard = context
        keyboard.clip(to: deck)
        for row in 0..<2 {
            let y = -8.4 + Double(row) * 2.4
            let inset = 1.2 * Double(row)
            for x in stride(from: -21.5 - inset, through: 19 + inset, by: 3.1) {
                keyboard.fill(Path(roundedRect: CGRect(x: x, y: y, width: 2.4, height: 1.5), cornerRadius: 0.4), with: .color(Palette.key))
            }
        }
        keyboard.fill(Path(roundedRect: CGRect(x: -6, y: -3.8, width: 12, height: 1.8), cornerRadius: 0.8), with: .color(Palette.silver.shade))

        drawHand(in: context, at: CGPoint(x: -1, y: 1.8), angle: -96, thumb: 1, ink: ink)
    }

    /// What's on screen tells you how he's doing.
    private func drawScreen(in context: GraphicsContext, rect: CGRect) {
        var screen = context
        screen.clip(to: Path(rect))
        screen.fill(Path(rect), with: .color(screenBackground))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        switch mood {
        case .cheerful:
            drawCode(in: screen, rect: rect)
        case .excited:
            // Hovered: the command is typed, one keypress from running.
            screen.draw(Text("$ drink").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(Palette.terminal),
                        at: CGPoint(x: rect.minX + 3, y: rect.minY + 4), anchor: .topLeading)
            if sin(time * 9) > 0 {
                screen.fill(Path(CGRect(x: rect.minX + 3.4, y: rect.minY + 14, width: 3.6, height: 6)), with: .color(Palette.terminal))
            }
        case .pleading:
            // Forever 99%.
            screen.draw(Text("99%").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white),
                        at: center + CGPoint(x: 0, y: -5))
            let bar = CGRect(x: rect.minX + 5, y: rect.midY + 3, width: rect.width - 10, height: 4.6)
            screen.stroke(Path(roundedRect: bar, cornerRadius: 2.3), with: .color(.white.opacity(0.55)), lineWidth: 0.8)
            let filled = CGRect(x: bar.minX + 1.1, y: bar.minY + 1.1, width: (bar.width - 2.2) * (0.97 + 0.006 * sin(time * 3)), height: bar.height - 2.2)
            screen.fill(Path(roundedRect: filled, cornerRadius: 1.2), with: .color(glow))
            let shimmer = (time * 0.8).truncatingRemainder(dividingBy: 1)
            var shine = screen
            shine.clip(to: Path(roundedRect: filled, cornerRadius: 1.2))
            shine.fill(Path(CGRect(x: filled.minX + filled.width * shimmer - 3, y: filled.minY, width: 3, height: filled.height)),
                       with: .color(.white.opacity(0.6)))
        case .thirsty:
            // 404: water not found, on a flickering screen.
            screen.opacity = Self.noise(Int(time * 12)) > 0.85 ? 0.5 : 1
            for y in stride(from: rect.minY, to: rect.maxY, by: 2) {
                screen.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: 0.7)), with: .color(.white.opacity(0.05)))
            }
            screen.draw(Text("404").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundColor(Palette.error),
                        at: center + CGPoint(x: 0, y: -4))
            screen.draw(Text("NO H₂O").font(.system(size: 5.5, weight: .heavy, design: .monospaced)).foregroundColor(Palette.error.opacity(0.85)),
                        at: center + CGPoint(x: 0, y: 8))
        case .delighted:
            var check = Path()
            check.move(to: center + CGPoint(x: -6.5, y: -5))
            check.addLine(to: center + CGPoint(x: -2, y: -0.5))
            check.addLine(to: center + CGPoint(x: 7, y: -10))
            screen.stroke(check, with: .color(Palette.success), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            screen.draw(Text("200 OK").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(Palette.success),
                        at: center + CGPoint(x: 0, y: 8))
        case .sleepy:
            // Screensaver: a droplet bouncing off the edges.
            func bounce(_ value: Double) -> CGFloat {
                let phase = value.truncatingRemainder(dividingBy: 2)
                return CGFloat(phase < 1 ? phase : 2 - phase)
            }
            let x = rect.minX + 3 + (rect.width - 12) * bounce(time * 0.4)
            let y = rect.minY + 3 + (rect.height - 14) * bounce(time * 0.31 + 0.4)
            screen.fill(DropShape().path(in: CGRect(x: x, y: y, width: 6, height: 8.5)), with: .color(Bottle.water.opacity(0.7)))
        case .tickled:
            // Poked mid-build: the screen glitches out.
            let frame = Int(time * 14)
            for index in 0..<7 {
                let y = rect.minY + rect.height * Self.noise(frame * 7 + index)
                let height = 1 + 3 * Self.noise(frame * 13 + index)
                let x = rect.minX + 10 * (Self.noise(frame * 5 + index) - 0.5)
                screen.fill(Path(CGRect(x: x, y: y, width: rect.width, height: height)),
                            with: .color(Palette.glitch[index % Palette.glitch.count].opacity(0.55)))
            }
            let text = Text("XD").font(.system(size: 13, weight: .black, design: .rounded))
            screen.draw(text.foregroundColor(Palette.glitch[0]), at: center + CGPoint(x: -1.3, y: 0))
            screen.draw(text.foregroundColor(Palette.glitch[1]), at: center + CGPoint(x: 1.3, y: 0))
            screen.draw(text.foregroundColor(.white), at: center)
        }
        // A sheen across the glass.
        var sheen = Path()
        sheen.move(to: CGPoint(x: rect.minX, y: rect.minY))
        sheen.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY))
        sheen.addLine(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY))
        sheen.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        sheen.closeSubpath()
        screen.fill(sheen, with: .color(.white.opacity(0.06)))
    }

    /// The editor types this out while he waits: per line, an indent and
    /// tokens as (length in characters, syntax color).
    private static let code: [(indent: Int, tokens: [(length: Int, color: Int)])] = [
        (0, [(4, 0), (7, 1), (2, 3)]),
        (1, [(3, 0), (4, 3), (1, 3), (5, 2)]),
        (1, [(2, 0), (7, 1), (1, 3)]),
        (2, [(5, 1), (2, 3)]),
        (1, [(1, 3)]),
        (0, [(2, 4), (9, 4)]),
    ]

    private func drawCode(in context: GraphicsContext, rect: CGRect) {
        let cell: CGFloat = 1.75
        let lineHeight: CGFloat = 4.6
        let total = Self.code.reduce(0) { sum, line in sum + line.tokens.reduce(0) { $0 + $1.length + 1 } }
        // Types the file out, pauses on it, then starts over.
        var remaining = (time * 14).truncatingRemainder(dividingBy: Double(total + 24))
        var cursor = CGPoint(x: rect.minX + 5.5, y: rect.minY + 3.6)
        typing: for (index, line) in Self.code.enumerated() {
            let y = rect.minY + 3.6 + CGFloat(index) * lineHeight
            context.fill(Path(roundedRect: CGRect(x: rect.minX + 1.4, y: y - 0.6, width: 2, height: 1.2), cornerRadius: 0.5),
                         with: .color(.white.opacity(0.18)))
            var x = rect.minX + 5.5 + CGFloat(line.indent) * 2 * cell
            for token in line.tokens {
                guard remaining > 0 else { break typing }
                let shown = CGFloat(min(Double(token.length), remaining))
                context.fill(Path(roundedRect: CGRect(x: x, y: y - 1, width: shown * cell - 0.4, height: 2), cornerRadius: 1),
                             with: .color(Palette.syntax[token.color]))
                cursor = CGPoint(x: x + shown * cell + 0.3, y: y)
                remaining -= Double(token.length + 1)
                x += CGFloat(token.length + 1) * cell
            }
        }
        if sin(time * 9) > 0 {
            context.fill(Path(CGRect(x: cursor.x, y: cursor.y - 1.7, width: 1.1, height: 3.4)), with: .color(.white))
        }
    }

    private var screenBackground: Color {
        switch mood {
        case .thirsty: return Color(hex: 0x2A0D14)
        case .delighted: return Color(hex: 0x0D2A1E)
        case .sleepy: return Color(hex: 0x080A14)
        case .excited: return Color(hex: 0x0B1210)
        default: return Color(hex: 0x1B2030)
        }
    }

    /// The screen's color, which also lights his face and his glasses.
    private var glow: Color {
        switch mood {
        case .cheerful: return Color(hex: 0x6CB6FF)
        case .excited: return Palette.terminal
        case .pleading: return Color(hex: 0xFFB35C)
        case .thirsty: return Palette.error
        case .delighted: return Palette.success
        case .sleepy: return Color(hex: 0x5A6BD8)
        case .tickled: return Color(hue: (time * 1.5).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 1)
        }
    }

    private var glowStrength: Double { mood == .sleepy ? 0.4 : 1 }

    /// A repeatable 0…1 jitter, for flicker and glitches.
    private static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return value - value.rounded(.down)
    }

    // MARK: Bottle

    /// Bottle center and tilt, eased between "at his side" and "at the mouth".
    private func bottlePose(wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let angle = 10 + (-95 - 10) * Double(eased) + wiggle
        let rest = CGPoint(x: 135, y: 151)
        let drinking = Self.mouth - Bottle.offset(Bottle.neck, angle: -95)
        return (rest + (drinking - rest) * eased, angle)
    }

    // MARK: Motion

    private var blink: CGFloat {
        time.truncatingRemainder(dividingBy: 4.6) > 4.44 ? 0 : 1
    }

    /// Per-mood body language, plus a bounce on the coiled cable as he drops in.
    private struct Motion {
        var swing = 0.0
        var lift: CGFloat = 0
        var headTilt = 0.0
        var legLeft = 0.0
        var legRight = 0.0
        var wiggle = 0.0
        /// How the laptop leans in his hand; it sags as he flags.
        var laptopTilt = 0.0
        /// The cowlick's lean, in degrees: up when he's perky, flopped over when he's not.
        var cowlick = 0.0
        /// How far his glasses have slid down his nose.
        var glassesDrop: CGFloat = 0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 3 * sin(t * 1.4)
                headTilt = 4 * sin(t * 1.1 + 0.5)
                legLeft = 7 * sin(t * 2)
                legRight = 7 * sin(t * 2 + 1.3)
                laptopTilt = -5 + 2 * sin(t * 1.4)
                cowlick = 8 * sin(t * 2.2)
                glassesDrop = 1
            case .excited:
                swing = 1.5 * sin(t * 2)
                lift = -4 * abs(sin(t * 6))
                headTilt = 4 * sin(t * 3)
                legLeft = 16 * sin(t * 7)
                legRight = 16 * sin(t * 7 + .pi)
                laptopTilt = 4 * sin(t * 6)
                cowlick = 16 + 6 * sin(t * 12)
            case .pleading:
                swing = 2.5 * sin(t * 1.5)
                headTilt = 9 + 2 * sin(t * 1.2)
                legLeft = 4 * sin(t * 2)
                legRight = 4 * sin(t * 2 + 1)
                laptopTilt = -8 + 1.5 * sin(t * 1.5)
                cowlick = -20 + 5 * sin(t * 2)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 2
                headTilt = -8 + 1.5 * sin(t * 0.8)
                legLeft = 2 * sin(t * 0.9)
                legRight = 2 * sin(t * 0.9 + 0.8)
                laptopTilt = -13 + 2 * sin(t * 0.8)
                cowlick = -75 + 4 * sin(t * 0.8)
                glassesDrop = 2
            case .delighted:
                swing = 5 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                headTilt = 4 * sin(t * 3)
                legLeft = 14 * sin(t * 6)
                legRight = 14 * sin(t * 6 + .pi)
                laptopTilt = 5 * sin(t * 5)
                cowlick = 20 + 10 * sin(t * 10)
            case .sleepy:
                swing = 1.2 * sin(t * 0.7)
                headTilt = -12 + 2 * sin(t * 0.9)
                legLeft = 2 * sin(t * 0.7)
                legRight = 2 * sin(t * 0.7 + 0.5)
                laptopTilt = -14 + 1.5 * sin(t * 0.7)
                cowlick = -85
                glassesDrop = 4.5
            case .tickled:
                swing = 6 * sin(t * 26)
                lift = -3
                headTilt = 9 * sin(t * 18)
                legLeft = 22 * sin(t * 12)
                legRight = 22 * sin(t * 12 + .pi)
                laptopTilt = 8 * sin(t * 20)
                cowlick = 25 * sin(t * 30)
                glassesDrop = -2.5 * abs(sin(t * 18))
            }
            // Bungee: the coiled cable stretches as he drops in, then bobs until it settles.
            lift += CGFloat(12 * exp(-2.4 * t) * sin(t * 10))
        }
    }

    enum Palette {
        static let ink = Color(hex: 0x1F1A26)
        static let inkStyle = Ink(color: ink)
        static let skin = Tone(0xF3C9A6, shade: 0xD9A27F, light: 0xFFE5D0)
        static let hair = Tone(0x4A3631, shade: 0x2E211E, light: 0x7A5A50)
        static let hoodie = Tone(0x3F8F7E, shade: 0x2C6A5D, light: 0x72C4AF)
        static let hoodieDeep = Tone(0x317566, shade: 0x22574B, light: 0x5AA896)
        static let pants = Tone(0x3B4562, shade: 0x293048, light: 0x5E6B8E)
        static let pantsCuff = Tone(0x323A54, shade: 0x22283C, light: 0x4F5A78)
        static let sneaker = Tone(0xF4F1EA, shade: 0xCFC7B8, light: 0xFFFFFF)
        static let clay = Tone(0xD97757, shade: 0xB65A3B, light: 0xF0A587)
        static let band = Tone(0x5A6078, shade: 0x3C4152, light: 0x8B93AD)
        static let silver = Tone(0xC9CED8, shade: 0x969DAB, light: 0xF1F3F7)
        static let silverEdge = Tone(0xA3AAB7, shade: 0x7D8494, light: 0xCDD2DB)
        static let tongueTone = Tone(0xF08A8A, shade: 0xD06868, light: 0xFFB3B3)
        static let bezel = Color(hex: 0x14161C)
        static let key = Color(hex: 0x4B5160)
        static let frame = Color(hex: 0x231D29)
        static let pupil = Color(hex: 0x2A1F2B)
        static let eyeBag = Color(hex: 0x9C7FA0)
        static let mouth = Color(hex: 0x6B2A2C)
        static let tongue = Color(hex: 0xF08A8A)
        static let blush = Color(hex: 0xF29C8F)
        static let string = Color(hex: 0xF4F1EA)
        static let print = Color.white.opacity(0.85)
        static let terminal = Color(hex: 0x6DFFB0)
        static let error = Color(hex: 0xFF4D5E)
        static let success = Color(hex: 0x4CE08A)
        /// Keyword, function, string, plain, comment.
        static let syntax: [Color] = ([0xFF79C6, 0x82AAFF, 0xC3E88D, 0xD6DEEB, 0x6A7A90] as [UInt32]).map { Color(hex: $0) }
        static let glitch: [Color] = ([0xFF3B6B, 0x3BE8FF, 0xFFE14D, 0x6DFFB0] as [UInt32]).map { Color(hex: $0) }
        static let bottle = Bottle(cap: hoodie, label: Color(hex: 0xD97757))
    }
}

#Preview {
    TimelineView(.animation) { context in
        let time = context.date.timeIntervalSinceReferenceDate
        HStack(spacing: 8) {
            ForEach(WaterBotMood.allCases, id: \.self) { mood in
                DevFigure(mood: mood, time: time)
            }
        }
    }
    .padding(30)
    .background(Color(hex: 0x2A2438))
}
