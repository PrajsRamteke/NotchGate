import SwiftUI

/// The water bot's caped stand-in, drawn in code: a chibi Batman lowering
/// himself from the notch on his grapnel line, cape scalloped like bat wings,
/// the bottle in his free hand. White eye slits and the exposed jaw carry the
/// mood. Like `WaterBotFigure`, everything is a function of `mood` and `time`.
struct BatFigure: View {
    var mood: WaterBotMood
    /// Seconds since Batman appeared; drives the idle motion.
    var time: TimeInterval
    /// 0 = bottle at his side, 1 = tipped to the mouth.
    var sip: CGFloat = 0
    /// How full the bottle is, 0…1.
    var waterLevel: CGFloat = 0.8

    static let size = WaterBotFigure.size
    /// Where the grapnel line leaves the top edge; Batman swings around it.
    static let ropeAnchor = CGPoint(x: 44, y: 0)
    /// Where the bottle meets the mouth, for the splash when you drink.
    static let mouth = CGPoint(x: 90, y: 106)

    var body: some View {
        let motion = Motion(mood: mood, time: time)
        Canvas { context, _ in
            draw(in: context, motion: motion)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // A cool rim of light so the dark suit holds its shape on dark wallpaper.
        .shadow(color: Color(hex: 0x9DB4D8).opacity(0.28), radius: 6)
        .shadow(color: .black.opacity(0.45), radius: 5, y: 4)
        .rotationEffect(
            .degrees(motion.swing),
            anchor: UnitPoint(x: Self.ropeAnchor.x / Self.size.width, y: 0)
        )
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static let fist = CGPoint(x: 44, y: 54)
    private static let headCenter = CGPoint(x: 90, y: 84)
    private static let neck = CGPoint(x: 90, y: 116)
    private static let leftShoulder = CGPoint(x: 71, y: 122)
    private static let rightShoulder = CGPoint(x: 109, y: 122)

    private var ink: Ink { Palette.inkStyle }

    private func draw(in context: GraphicsContext, motion: Motion) {
        var body = context
        body.translateBy(x: 0, y: motion.lift)
        let fist = Self.fist + CGPoint(x: 0, y: motion.lift)

        drawLine(in: context, to: fist + CGPoint(x: 0, y: -28))
        drawCape(in: body, motion: motion)
        drawLegs(in: body, motion: motion)
        drawTorso(in: body)

        var head = body
        head.translateBy(x: Self.neck.x, y: Self.neck.y)
        head.rotate(by: .degrees(motion.headTilt))
        head.translateBy(x: Self.headCenter.x - Self.neck.x, y: Self.headCenter.y - Self.neck.y)
        drawHead(in: head, ink: ink.turned(by: motion.headTilt))
        drawMoodExtras(in: body)

        let (bottleCenter, bottleAngle) = bottlePose(wiggle: motion.wiggle)
        let grip = bottleCenter + Bottle.offset(CGPoint(x: -6, y: 7), angle: bottleAngle)
        drawArm(in: body, from: Self.rightShoulder, to: grip, bend: -0.2, outward: -1)
        Palette.bottle.draw(in: body, center: bottleCenter, angle: bottleAngle, level: waterLevel, time: time, ink: ink, capped: sip < 0.3)
        drawGlove(in: body, at: grip, angle: bottleAngle - 10, thumb: -1)

        drawGrapnel(in: body)
        drawArm(in: body, from: Self.leftShoulder, to: Self.fist, bend: 0.14, outward: -1)
        drawGlove(in: body, at: Self.fist, angle: -80, thumb: 1)
    }

    /// The grapnel line, taut from the notch to the gun.
    private func drawLine(in context: GraphicsContext, to end: CGPoint) {
        var line = Path()
        line.move(to: CGPoint(x: Self.ropeAnchor.x, y: -6))
        line.addLine(to: end)
        context.stroke(line, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        context.stroke(line, with: .color(Color(hex: 0xC9D2DE)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    /// The grapnel gun, barrel up, the line running out of its muzzle.
    private func drawGrapnel(in context: GraphicsContext) {
        let fist = Self.fist
        let barrel = Path(roundedRect: CGRect(x: fist.x - 4, y: fist.y - 27, width: 8, height: 16), cornerRadius: 2)
        let muzzle = Path(roundedRect: CGRect(x: fist.x - 5.5, y: fist.y - 30, width: 11, height: 5.5), cornerRadius: 1.8)
        let body = Sketch.rounded([
            CGPoint(x: fist.x - 7, y: fist.y - 14), CGPoint(x: fist.x + 7, y: fist.y - 14),
            CGPoint(x: fist.x + 9, y: fist.y - 4), CGPoint(x: fist.x - 7, y: fist.y - 4),
        ], radius: 2.5)
        ink.paint([(barrel, Palette.gunmetal), (body, Palette.gunmetal), (muzzle, Palette.gunmetal)], in: context)
        for y in [fist.y - 22, fist.y - 18] {
            var band = Path()
            band.move(to: CGPoint(x: fist.x - 4, y: y))
            band.addLine(to: CGPoint(x: fist.x + 4, y: y))
            ink.crease(band, in: context, width: 0.9, opacity: 0.6)
        }
        context.fill(Path(roundedRect: CGRect(x: fist.x + 1, y: fist.y - 11, width: 5.5, height: 2.2), cornerRadius: 1.1),
                     with: .color(Palette.gold.base))
    }

    // MARK: Cape

    /// Hangs from the shoulders behind him, its hem scalloped like bat wings.
    private func drawCape(in context: GraphicsContext, motion: Motion) {
        let t = time
        let flutter = motion.flutter
        var hem: [CGPoint] = []
        for index in 0...5 {
            let x = 44 + Double(index) * 19 + flutter * 3 * sin(t * 3 + Double(index))
            let y = 186 - abs(Double(index) - 2.5) * 2.2 + flutter * 2.5 * sin(t * 2.4 + Double(index) * 1.3)
            hem.append(CGPoint(x: x, y: y))
        }
        var cape = Path()
        cape.move(to: CGPoint(x: 70, y: 108))
        cape.addQuadCurve(to: hem[0], control: CGPoint(x: 48 + flutter * 2 * sin(t * 2), y: 140))
        for index in 1..<hem.count {
            let mid = (hem[index - 1] + hem[index]) * 0.5
            cape.addQuadCurve(to: hem[index], control: mid + CGPoint(x: 0, y: -9))
        }
        cape.addQuadCurve(to: CGPoint(x: 110, y: 108), control: CGPoint(x: 136 + flutter * 2 * sin(t * 2 + 1), y: 140))
        cape.closeSubpath()
        ink.paint(cape, Palette.cape, in: context)

        // Folds running down to the points of the hem.
        for index in 1..<(hem.count - 1) {
            var fold = Path()
            let top = CGPoint(x: 80 + Double(index - 1) * 6.5, y: 124)
            fold.move(to: top)
            fold.addQuadCurve(to: hem[index] + CGPoint(x: 0, y: -4), control: (top + hem[index]) * 0.5 + CGPoint(x: 3, y: 0))
            ink.crease(fold, in: context, width: 0.9, opacity: 0.55)
        }
    }

    // MARK: Body

    private func drawLegs(in context: GraphicsContext, motion: Motion) {
        for (hip, angle) in [(CGPoint(x: 82, y: 148), motion.legLeft), (CGPoint(x: 98, y: 148), motion.legRight)] {
            let foot = hip + CGPoint(x: 0, y: 28).rotated(by: angle)
            let leg = Sketch.limb(hip, (hip + foot) * 0.5, foot, 6.2, 5.2)
            let toe = Sketch.limb(foot, foot + CGPoint(x: 1, y: 3).rotated(by: angle), foot + CGPoint(x: 2.5, y: 5).rotated(by: angle), 5.4, 4.4)
            let boot = leg.intersection(bootRegion(from: hip, to: foot, at: 0.52)).union(toe)
            ink.paint(leg, Palette.suit, in: context)
            ink.paint(boot, Palette.black, in: context)
        }
    }

    /// The part of a limb past `fraction` of the way to its end, cuffed with a
    /// shallow point (boots and gloves).
    private func bootRegion(from start: CGPoint, to end: CGPoint, at fraction: CGFloat) -> Path {
        let along = (end - start).normalized
        let across = CGPoint(x: -along.y, y: along.x)
        let cuff = start + (end - start) * fraction
        var region = Path()
        region.move(to: cuff + across * 14 - along * 2)
        region.addLine(to: cuff + along * 1.5)
        region.addLine(to: cuff - across * 14 - along * 2)
        region.addLine(to: cuff - across * 14 + along * 60)
        region.addLine(to: cuff + across * 14 + along * 60)
        region.closeSubpath()
        return region
    }

    private func drawTorso(in context: GraphicsContext) {
        let torso = Sketch.rounded([
            CGPoint(x: 69, y: 114), CGPoint(x: 111, y: 114), CGPoint(x: 104, y: 152), CGPoint(x: 76, y: 152),
        ], radius: 9)
        ink.paint(torso, Palette.suit, in: context)

        var suit = context
        suit.clip(to: torso)
        // Utility belt: gold, with pouches and a buckle.
        let belt = Path(CGRect(x: 70, y: 141, width: 40, height: 8))
        ink.shade(belt, Palette.gold, in: suit)
        ink.crease(belt, in: suit, width: 1, opacity: 0.8)
        for x in [77.0, 99.0] {
            let pouch = Path(roundedRect: CGRect(x: x, y: 142, width: 5, height: 8), cornerRadius: 1.4)
            ink.paint(pouch, Palette.gold, in: suit)
        }
        let buckle = Ellipse().path(in: CGRect(center: CGPoint(x: 90, y: 145), width: 9, height: 7))
        ink.paint(buckle, Palette.gold, in: suit)

        drawEmblem(in: suit, at: CGPoint(x: 90, y: 128), width: 27)
        ink.gloss(CGRect(x: 74, y: 117, width: 10, height: 6), in: suit, opacity: 0.25, angle: -15)
    }

    /// The bat on his chest.
    private func drawEmblem(in context: GraphicsContext, at center: CGPoint, width: CGFloat) {
        // Right half, from between the ears down to the tail point; mirrored for the left.
        let start = CGPoint(x: 0, y: -2.6)
        let segments: [(to: CGPoint, control: CGPoint?)] = [
            (CGPoint(x: 1.7, y: -5.8), nil),
            (CGPoint(x: 2.7, y: -2.3), nil),
            (CGPoint(x: 13, y: -5.2), CGPoint(x: 7.5, y: -0.8)),
            (CGPoint(x: 10.6, y: 0.4), CGPoint(x: 12.6, y: -1.8)),
            (CGPoint(x: 7.4, y: 0.9), CGPoint(x: 9, y: -1.4)),
            (CGPoint(x: 4.4, y: 3.8), CGPoint(x: 5.1, y: 0.9)),
            (CGPoint(x: 0, y: 6), CGPoint(x: 1.8, y: 3.4)),
        ]
        func mirrored(_ point: CGPoint) -> CGPoint { CGPoint(x: -point.x, y: point.y) }
        var bat = Path()
        bat.move(to: start)
        for segment in segments {
            if let control = segment.control { bat.addQuadCurve(to: segment.to, control: control) } else { bat.addLine(to: segment.to) }
        }
        let points = [start] + segments.map(\.to)
        for index in stride(from: segments.count - 1, through: 0, by: -1) {
            let target = mirrored(points[index])
            if let control = segments[index].control { bat.addQuadCurve(to: target, control: mirrored(control)) } else { bat.addLine(to: target) }
        }
        bat.closeSubpath()
        let scale = width / 26
        context.fill(bat.applying(CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)), with: .color(Palette.ink))
    }

    // MARK: Head (drawn around the origin; the caller places and tilts it)

    private static let skull: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -34))
        path.addCurve(to: CGPoint(x: 38, y: -1), control1: CGPoint(x: 23, y: -34), control2: CGPoint(x: 38, y: -21))
        path.addCurve(to: CGPoint(x: 0, y: 34), control1: CGPoint(x: 38, y: 19), control2: CGPoint(x: 21, y: 34))
        path.addCurve(to: CGPoint(x: -38, y: -1), control1: CGPoint(x: -21, y: 34), control2: CGPoint(x: -38, y: 19))
        path.addCurve(to: CGPoint(x: 0, y: -34), control1: CGPoint(x: -38, y: -21), control2: CGPoint(x: -23, y: -34))
        path.closeSubpath()
        return path
    }()

    private static func ear(_ side: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 30 * side, y: -18))
        path.addQuadCurve(to: CGPoint(x: 25 * side, y: -50), control: CGPoint(x: 31 * side, y: -36))
        path.addQuadCurve(to: CGPoint(x: 11 * side, y: -31), control: CGPoint(x: 20 * side, y: -38))
        path.closeSubpath()
        return path
    }

    private static let cowl = skull.union(ear(-1)).union(ear(1))

    /// The cowl's lower edge comes down over the nose, open at the mouth and jaw.
    private static let face: Path = {
        var opening = Path()
        opening.move(to: CGPoint(x: -31, y: 30))
        opening.addLine(to: CGPoint(x: -28, y: 11))
        opening.addQuadCurve(to: CGPoint(x: -6, y: 8), control: CGPoint(x: -17, y: 7))
        opening.addLine(to: CGPoint(x: 0, y: 13))
        opening.addLine(to: CGPoint(x: 6, y: 8))
        opening.addQuadCurve(to: CGPoint(x: 28, y: 11), control: CGPoint(x: 17, y: 7))
        opening.addLine(to: CGPoint(x: 31, y: 30))
        opening.addLine(to: CGPoint(x: 0, y: 46))
        opening.closeSubpath()
        return skull.intersection(opening)
    }()

    private func drawHead(in context: GraphicsContext, ink: Ink) {
        let cowl = Self.cowl
        ink.paint(cowl, Palette.black, in: context)
        let face = Self.face
        ink.shade(face, Palette.skin, in: context)
        ink.crease(face, in: context, width: 1.3, opacity: 1)

        var cowlSurface = context
        cowlSurface.clip(to: cowl)
        ink.gloss(CGRect(x: -28, y: -28, width: 22, height: 8), in: cowlSurface, opacity: 0.16, angle: -25)

        drawFace(in: context, ink: ink)
    }

    private func drawFace(in context: GraphicsContext, ink: Ink) {
        if [.delighted, .tickled, .excited].contains(mood) {
            for side in [-1.0, 1.0] {
                context.fill(Ellipse().path(in: CGRect(center: CGPoint(x: 17 * side, y: 19), width: 8, height: 4)),
                             with: .color(Palette.blush.opacity(0.7)))
            }
        }
        for side in [-1.0, 1.0] {
            drawEye(in: context, side: side, ink: ink)
        }
        drawMouth(in: context, at: CGPoint(x: 0, y: 23), ink: ink)
    }

    /// White slits under a hard brow; their shape is most of the expression.
    private func drawEye(in context: GraphicsContext, side: CGFloat, ink: Ink) {
        var eye = context
        eye.scaleBy(x: side, y: 1)
        let white = GraphicsContext.Shading.color(Palette.lens)
        let arcStyle = StrokeStyle(lineWidth: 2.6, lineCap: .round)

        switch mood {
        case .delighted:
            var arc = Path()
            arc.move(to: CGPoint(x: 7, y: -1))
            arc.addQuadCurve(to: CGPoint(x: 21, y: -2), control: CGPoint(x: 14, y: -10))
            eye.stroke(arc, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            eye.stroke(arc, with: white, style: arcStyle)
            return
        case .sleepy:
            var shut = Path()
            shut.move(to: CGPoint(x: 7, y: -2))
            shut.addQuadCurve(to: CGPoint(x: 21, y: -3), control: CGPoint(x: 14, y: 2))
            eye.stroke(shut, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 4.4, lineCap: .round))
            eye.stroke(shut, with: white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            return
        case .tickled:
            var chevron = Path()
            chevron.move(to: CGPoint(x: 20, y: -9))
            chevron.addLine(to: CGPoint(x: 9, y: -3.5))
            chevron.addLine(to: CGPoint(x: 20, y: 2))
            eye.stroke(chevron, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            eye.stroke(chevron, with: white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            return
        default:
            break
        }

        let corners: [CGPoint]
        switch mood {
        case .excited:
            corners = [CGPoint(x: 6, y: -5), CGPoint(x: 21, y: -11), CGPoint(x: 21.5, y: 1.5), CGPoint(x: 7, y: 2)]
        case .pleading:
            corners = [CGPoint(x: 6.5, y: -8), CGPoint(x: 20.5, y: -5.5), CGPoint(x: 20, y: 1.5), CGPoint(x: 7.5, y: 1.5)]
        case .thirsty:
            corners = [CGPoint(x: 6, y: -2), CGPoint(x: 21, y: -3.5), CGPoint(x: 20.5, y: 0.5), CGPoint(x: 7, y: 1)]
        default:
            corners = [CGPoint(x: 6, y: -3), CGPoint(x: 21.5, y: -9), CGPoint(x: 20.5, y: 0), CGPoint(x: 7, y: 1.2)]
        }
        var slit = eye
        if mood == .cheerful || mood == .pleading {
            slit.translateBy(x: 0, y: -3)
            slit.scaleBy(x: 1, y: blink)
            slit.translateBy(x: 0, y: 3)
        }
        let shape = Sketch.rounded(corners, radius: 2)
        slit.stroke(shape, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
        slit.fill(shape, with: .linearGradient(
            Gradient(colors: [Palette.lens, Palette.lensShade]),
            startPoint: CGPoint(x: 0, y: -10), endPoint: CGPoint(x: 0, y: 2)
        ))
        // The brow ridge sculpted into the cowl above it.
        var brow = Path()
        brow.move(to: corners[0] + CGPoint(x: -1, y: -3.5))
        brow.addLine(to: corners[1] + CGPoint(x: 1, y: -3.5))
        eye.stroke(brow, with: .color(Palette.black.light.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func drawMouth(in context: GraphicsContext, at mouth: CGPoint, ink: Ink) {
        switch mood {
        case .cheerful:
            // A confident half-smile.
            var smirk = Path()
            smirk.move(to: mouth + CGPoint(x: -5, y: 0))
            smirk.addQuadCurve(to: mouth + CGPoint(x: 5.5, y: -2.5), control: mouth + CGPoint(x: 1, y: 3))
            ink.crease(smirk, in: context, width: 1.6, opacity: 0.95)
        case .excited, .delighted, .tickled:
            if mood == .delighted && sip > 0.6 {
                context.fill(Ellipse().path(in: CGRect(center: mouth, width: 6, height: 5)), with: .color(Palette.mouth))
                return
            }
            let width: CGFloat = mood == .tickled ? 7 : 6
            var grin = Path()
            grin.move(to: mouth + CGPoint(x: -width, y: -2))
            grin.addQuadCurve(to: mouth + CGPoint(x: width, y: -2), control: mouth + CGPoint(x: 0, y: -3))
            grin.addQuadCurve(to: mouth + CGPoint(x: -width, y: -2), control: mouth + CGPoint(x: 0, y: 9 + (mood == .tickled ? 1.5 * sin(time * 20) : 0)))
            grin.closeSubpath()
            context.fill(grin, with: .color(Palette.mouth))
            var teeth = context
            teeth.clip(to: grin)
            teeth.fill(Path(CGRect(x: mouth.x - width, y: mouth.y - 4, width: width * 2, height: 3.4)), with: .color(.white))
            ink.crease(grin, in: context, width: 1.2, opacity: 0.95)
        case .pleading:
            var wobble = Path()
            wobble.move(to: mouth + CGPoint(x: -4, y: 1))
            wobble.addQuadCurve(to: mouth + CGPoint(x: 4, y: 1), control: mouth + CGPoint(x: 0, y: -3))
            ink.crease(wobble, in: context, width: 1.6, opacity: 0.95)
        case .thirsty:
            var wave = Path()
            wave.move(to: mouth + CGPoint(x: -6, y: 0))
            wave.addQuadCurve(to: mouth, control: mouth + CGPoint(x: -3, y: -2.5))
            wave.addQuadCurve(to: mouth + CGPoint(x: 6, y: 0), control: mouth + CGPoint(x: 3, y: 2.5))
            ink.crease(wave, in: context, width: 1.6, opacity: 0.95)
        case .sleepy:
            let snore = 2.6 + 1.2 * sin(time * 2)
            context.fill(Ellipse().path(in: CGRect(center: mouth, width: snore, height: snore)), with: .color(Palette.mouth))
        }
    }

    /// Sweat when thirsty, floating z's when sleepy.
    private func drawMoodExtras(in context: GraphicsContext) {
        let head = Self.headCenter
        switch mood {
        case .thirsty:
            let drip = (time * 0.6).truncatingRemainder(dividingBy: 1)
            let top = CGPoint(x: head.x + 36, y: head.y - 14 + drip * 12)
            let drop = DropShape().path(in: CGRect(x: top.x - 4, y: top.y, width: 8, height: 11))
            var sweat = context
            sweat.opacity = 1 - drip * 0.6
            sweat.stroke(drop, with: .color(Palette.ink), lineWidth: 2)
            sweat.fill(drop, with: .color(Bottle.water))
        case .sleepy:
            for index in 0..<3 {
                let phase = (time * 0.45 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                let point = CGPoint(x: head.x + 40 + phase * 14, y: head.y - 26 - phase * 24)
                var snore = context
                snore.opacity = sin(phase * .pi)
                snore.draw(
                    Text("z").font(.system(size: 9 + phase * 6, weight: .heavy, design: .rounded)).foregroundColor(Palette.lens),
                    at: point
                )
            }
        default:
            break
        }
    }

    // MARK: Arms

    /// Grey sleeve into a black gauntlet with three fins down its outer edge.
    private func drawArm(in context: GraphicsContext, from shoulder: CGPoint, to hand: CGPoint, bend: CGFloat, outward: CGFloat) {
        let control = Sketch.elbow(shoulder, hand, bend: bend)
        let arm = Sketch.limb(shoulder, control, hand, 5.6, 4.6)
        let cuff = Sketch.quad(shoulder, control, hand, 0.55)
        let gauntlet = arm.intersection(bootRegion(from: cuff, to: hand, at: 0))

        var fins = Path()
        for t in [0.6, 0.71, 0.82] as [CGFloat] {
            let point = Sketch.quad(shoulder, control, hand, t)
            let along = ((control - shoulder) * (1 - t) + (hand - control) * t).normalized
            let side = CGPoint(x: -along.y, y: along.x) * outward
            let base = point + side * 3.6
            fins.move(to: base + along * 1.5)
            fins.addLine(to: base + side * 4 - along * 2.8)
            fins.addLine(to: base - along * 3.4)
            fins.closeSubpath()
        }
        ink.paint(fins, Palette.black, in: context)
        ink.paint(arm, Palette.suit, in: context)
        ink.paint(gauntlet, Palette.black, in: context)
    }

    private func drawGlove(in context: GraphicsContext, at point: CGPoint, angle: Double, thumb: CGFloat) {
        let hand = Sketch.mitten(at: point, radius: 6, angle: angle, thumb: thumb)
        ink.paint([(hand.thumb, Palette.black), (hand.palm, Palette.black)], in: context)
    }

    // MARK: Bottle

    /// Bottle center and tilt, eased between "at his side" and "at the mouth".
    private func bottlePose(wiggle: Double) -> (CGPoint, Double) {
        let eased = sip * sip * (3 - 2 * sip)
        let angle = 10 + (-95 - 10) * Double(eased) + wiggle
        let rest = CGPoint(x: 135, y: 150)
        let drinking = Self.mouth - Bottle.offset(Bottle.neck, angle: -95)
        return (rest + (drinking - rest) * eased, angle)
    }

    // MARK: Motion

    private var blink: CGFloat {
        time.truncatingRemainder(dividingBy: 4.2) > 4.06 ? 0.15 : 1
    }

    /// Per-mood body language: how he swings, kicks, tilts and how the cape moves.
    private struct Motion {
        var swing = 0.0
        var lift: CGFloat = 0
        var headTilt = 0.0
        var legLeft = 0.0
        var legRight = 0.0
        /// How much the cape stirs.
        var flutter = 1.0
        var wiggle = 0.0

        init(mood: WaterBotMood, time t: TimeInterval) {
            switch mood {
            case .cheerful:
                swing = 3 * sin(t * 1.5)
                headTilt = 3 * sin(t * 1.3 + 0.5)
                legLeft = 8 * sin(t * 2.2)
                legRight = 8 * sin(t * 2.2 + 1.3)
            case .excited:
                swing = 1.5 * sin(t * 2)
                lift = -4 * abs(sin(t * 6))
                headTilt = 4 * sin(t * 3)
                legLeft = 16 * sin(t * 7)
                legRight = 16 * sin(t * 7 + .pi)
                flutter = 1.8
            case .pleading:
                swing = 2.5 * sin(t * 1.5)
                headTilt = 8 + 2 * sin(t * 1.2)
                legLeft = 4 * sin(t * 2)
                legRight = 4 * sin(t * 2 + 1)
                let burst = t.truncatingRemainder(dividingBy: 2.6)
                wiggle = burst < 0.6 ? 14 * sin(burst * 22) : 0
            case .thirsty:
                swing = 2 * sin(t * 0.9)
                lift = 2
                headTilt = -7 + 1.5 * sin(t * 0.8)
                legLeft = 2 * sin(t * 0.9)
                legRight = 2 * sin(t * 0.9 + 0.8)
                flutter = 0.4
            case .delighted:
                swing = 5 * sin(t * 3.2)
                lift = -3 * abs(sin(t * 5))
                headTilt = 4 * sin(t * 3)
                legLeft = 14 * sin(t * 6)
                legRight = 14 * sin(t * 6 + .pi)
                flutter = 1.6
            case .sleepy:
                swing = 1.2 * sin(t * 0.7)
                headTilt = -10 + 2 * sin(t * 0.9)
                legLeft = 2 * sin(t * 0.7)
                legRight = 2 * sin(t * 0.7 + 0.5)
                flutter = 0.3
            case .tickled:
                swing = 6 * sin(t * 26)
                lift = -3
                headTilt = 9 * sin(t * 18)
                legLeft = 22 * sin(t * 12)
                legRight = 22 * sin(t * 12 + .pi)
                flutter = 2.4
            }
        }
    }

    enum Palette {
        static let ink = Color(hex: 0x0B0D12)
        static let inkStyle = Ink(color: ink)
        static let black = Tone(0x262D3B, shade: 0x161A23, light: 0x55637C)
        static let cape = Tone(0x202634, shade: 0x141821, light: 0x4A5770)
        static let suit = Tone(0x7C8798, shade: 0x5A6474, light: 0xA9B4C4)
        static let gunmetal = Tone(0x4B5260, shade: 0x313640, light: 0x7D8696)
        static let gold = Tone(0xF2BB3D, shade: 0xC88A1D, light: 0xFFE08C)
        static let skin = Tone(0xF2C6A2, shade: 0xD7A07D, light: 0xFFE3CD)
        static let lens = Color.white
        static let lensShade = Color(hex: 0xD3DEEC)
        static let mouth = Color(hex: 0x5E2424)
        static let blush = Color(hex: 0xF29C8F)
        static let bottle = Bottle(cap: black, label: Color(hex: 0xF2BB3D))
    }
}

#Preview {
    TimelineView(.animation) { context in
        let time = context.date.timeIntervalSinceReferenceDate
        HStack(spacing: 8) {
            ForEach(WaterBotMood.allCases, id: \.self) { mood in
                BatFigure(mood: mood, time: time)
            }
        }
    }
    .padding(30)
    .background(Color(hex: 0x2A2438))
}
