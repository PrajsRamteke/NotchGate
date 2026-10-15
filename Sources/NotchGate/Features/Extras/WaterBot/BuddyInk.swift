import SwiftUI

/// The drawing kit the water buddies share, so the robot, Spidey and Batman
/// read as one illustrated set: one ink weight, cel shading lit from the top
/// left, tapered limbs, mitten hands and the same bottle.
struct Ink {
    /// Outline color.
    var color: Color
    /// Outline weight, drawn just outside each shape.
    var width: CGFloat = 1.4
    /// Where the cel shadow falls; the light is up and to the left.
    var shadow = CGPoint(x: 2.6, y: 3.2)
    /// How far the rim light reaches in from the lit edge.
    var rim = CGPoint(x: 0.9, y: 1.1)

    /// The same light, for drawing in a context turned by `degrees`.
    func turned(by degrees: Double) -> Ink {
        var ink = self
        ink.shadow = shadow.rotated(by: -degrees)
        ink.rim = rim.rotated(by: -degrees)
        return ink
    }

    /// Outlines `path`, then fills it cel-shaded.
    func paint(_ path: Path, _ tone: Tone, in context: GraphicsContext) {
        outline(path, in: context)
        shade(path, tone, in: context)
    }

    /// Several parts as one silhouette: every outline first, then the fills,
    /// so the seams between the parts stay clean.
    func paint(_ parts: [(Path, Tone)], in context: GraphicsContext) {
        for (path, _) in parts { outline(path, in: context) }
        for (path, tone) in parts { shade(path, tone, in: context) }
    }

    func outline(_ path: Path, in context: GraphicsContext) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * 2, lineCap: .round, lineJoin: .round))
    }

    /// Base color, a rim light along the lit edge and a shadow crescent on the far side.
    func shade(_ path: Path, _ tone: Tone, in context: GraphicsContext) {
        var lit = context
        lit.clip(to: path)
        lit.fill(path, with: .color(tone.light))
        var shaded = lit
        shaded.clip(to: path.offsetBy(dx: rim.x, dy: rim.y))
        shaded.fill(path, with: .color(tone.shade))
        var base = shaded
        base.clip(to: path.offsetBy(dx: -shadow.x, dy: -shadow.y))
        base.fill(path, with: .color(tone.base))
    }

    /// A seam or crease inside a shape.
    func crease(_ path: Path, in context: GraphicsContext, width: CGFloat = 1, opacity: Double = 0.6) {
        context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A soft glossy highlight.
    func gloss(_ rect: CGRect, in context: GraphicsContext, opacity: Double = 0.5, angle: Double = 0) {
        let shape = Ellipse().path(in: rect).rotated(by: angle, around: CGPoint(x: rect.midX, y: rect.midY))
        context.fill(shape, with: .color(.white.opacity(opacity)))
    }
}

/// A painted material: its base color, the cel shadow on the side away from
/// the light, and the rim light along the lit edge.
struct Tone {
    var base: Color
    var shade: Color
    var light: Color

    init(_ base: UInt32, shade: UInt32, light: UInt32) {
        self.base = Color(hex: base)
        self.shade = Color(hex: shade)
        self.light = Color(hex: light)
    }
}

// MARK: - Shapes

enum Sketch {
    /// A limb along a quadratic curve: `startRadius` thick at `start`,
    /// tapering to `endRadius` at `end`, rounded at both ends.
    static func limb(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, _ startRadius: CGFloat, _ endRadius: CGFloat) -> Path {
        let steps = 20
        var left: [CGPoint] = [], right: [CGPoint] = []
        var firstNormal = CGPoint.zero, lastNormal = CGPoint.zero
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = quad(start, control, end, t)
            var tangent = (control - start) * (2 * (1 - t)) + (end - control) * (2 * t)
            if tangent.length < 0.001 { tangent = end - start }
            tangent = tangent.normalized
            let normal = CGPoint(x: -tangent.y, y: tangent.x)
            let radius = startRadius + (endRadius - startRadius) * t
            left.append(point + normal * radius)
            right.append(point - normal * radius)
            if step == 0 { firstNormal = normal }
            if step == steps { lastNormal = normal }
        }
        var path = Path()
        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        // Round caps, swept through the limb's forward (then backward) direction.
        let endAngle = atan2(lastNormal.y, lastNormal.x)
        for step in 1..<12 {
            let angle = endAngle - .pi * CGFloat(step) / 12
            path.addLine(to: end + CGPoint(x: cos(angle), y: sin(angle)) * endRadius)
        }
        for point in right.reversed() { path.addLine(to: point) }
        let startAngle = atan2(-firstNormal.y, -firstNormal.x)
        for step in 1..<12 {
            let angle = startAngle - .pi * CGFloat(step) / 12
            path.addLine(to: start + CGPoint(x: cos(angle), y: sin(angle)) * startRadius)
        }
        path.closeSubpath()
        return path
    }

    /// The point a fraction `t` along a quadratic curve.
    static func quad(_ start: CGPoint, _ control: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
        start * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + end * (t * t)
    }

    /// A control point that bows a limb from `start` to `end` sideways by
    /// `bend` (a fraction of its length; positive bows to the left of travel).
    static func elbow(_ start: CGPoint, _ end: CGPoint, bend: CGFloat) -> CGPoint {
        let span = end - start
        let normal = CGPoint(x: span.y, y: -span.x)
        return (start + end) * 0.5 + normal * bend
    }

    /// A polygon with its corners rounded off.
    static func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        for index in 0...count {
            let vertex = points[index % count]
            let previous = points[(index + count - 1) % count]
            let next = points[(index + 1) % count]
            let inbound = min(radius, (previous - vertex).length / 2)
            let outbound = min(radius, (next - vertex).length / 2)
            let from = vertex + (previous - vertex).normalized * inbound
            let to = vertex + (next - vertex).normalized * outbound
            if index == 0 { path.move(to: to); continue }
            path.addLine(to: from)
            path.addQuadCurve(to: to, control: vertex)
        }
        path.closeSubpath()
        return path
    }

    /// A mitten hand at `center`, fingers pointing along `angle` (degrees,
    /// 0 = right), thumb on the `thumb` side (+1 or -1).
    static func mitten(at center: CGPoint, radius: CGFloat, angle: Double, thumb: CGFloat) -> (palm: Path, thumb: Path) {
        let palm = Ellipse().path(in: CGRect(x: -radius * 1.08, y: -radius * 0.94, width: radius * 2.16, height: radius * 1.88))
        let thumbShape = Ellipse()
            .path(in: CGRect(x: -radius * 0.5, y: -radius * 0.3, width: radius, height: radius * 0.6))
            .rotated(by: -38 * Double(thumb), around: .zero)
            .offsetBy(dx: -radius * 0.05, dy: -radius * 0.82 * thumb)
        let place = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle * .pi / 180)
        return (palm.applying(place), thumbShape.applying(place))
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

// MARK: - Bottle

/// The water bottle every buddy carries: a molded bottle with a label, a
/// ridged cap, and water that stays level as it tips.
struct Bottle {
    var cap: Tone
    var label: Color

    static let water = Color(hex: 0xA6E1FF)
    static let waterDeep = Color(hex: 0x3D95E0)

    /// Bottle-space point (upright, centered) to an offset from its center when tipped.
    static func offset(_ point: CGPoint, angle: Double) -> CGPoint {
        point.rotated(by: angle)
    }

    /// Where the bottle's neck is in bottle space; tip this at a mouth to drink.
    static let neck = CGPoint(x: 0, y: -26)

    private static let silhouette: Path = {
        var path = Path()
        path.move(to: CGPoint(x: -6, y: -24))
        path.addLine(to: CGPoint(x: -6, y: -19.5))
        path.addCurve(to: CGPoint(x: -12, y: -9), control1: CGPoint(x: -6, y: -15.5), control2: CGPoint(x: -12, y: -14.5))
        path.addLine(to: CGPoint(x: -12, y: 17))
        path.addQuadCurve(to: CGPoint(x: -5, y: 24), control: CGPoint(x: -12, y: 24))
        path.addLine(to: CGPoint(x: 5, y: 24))
        path.addQuadCurve(to: CGPoint(x: 12, y: 17), control: CGPoint(x: 12, y: 24))
        path.addLine(to: CGPoint(x: 12, y: -9))
        path.addCurve(to: CGPoint(x: 6, y: -19.5), control1: CGPoint(x: 12, y: -14.5), control2: CGPoint(x: 6, y: -15.5))
        path.addLine(to: CGPoint(x: 6, y: -24))
        path.closeSubpath()
        return path
    }()

    /// `capped` false while drinking: the cap comes off.
    func draw(in context: GraphicsContext, center: CGPoint, angle: Double, level: CGFloat, time: TimeInterval, ink: Ink, capped: Bool = true) {
        var bottle = context
        bottle.translateBy(x: center.x, y: center.y)
        bottle.rotate(by: .degrees(angle))
        let shape = Self.silhouette

        bottle.stroke(shape, with: .color(ink.color), style: StrokeStyle(lineWidth: ink.width * 2, lineJoin: .round))
        bottle.fill(shape, with: .color(Color(hex: 0xDDEFFF).opacity(0.32)))

        // Water: its surface stays level with the world as the bottle tips.
        var glass = bottle
        glass.clip(to: shape)
        let fill = max(0, min(1, level))
        if fill > 0.01 {
            let up = CGPoint(x: 0, y: -1).rotated(by: -angle)
            let across = CGPoint(x: -up.y, y: up.x)
            let surface = CGPoint(x: 0, y: 24 - 46 * fill)
            var water = Path()
            water.move(to: surface - across * 40 - up * 80)
            for step in stride(from: -40.0, through: 40.0, by: 2.5) {
                let wave = 1.1 * sin(step / 4 + time * 5)
                water.addLine(to: surface + across * step + up * wave)
            }
            water.addLine(to: surface + across * 40 - up * 80)
            water.closeSubpath()
            glass.fill(water, with: .linearGradient(
                Gradient(colors: [Self.water, Self.waterDeep]),
                startPoint: surface, endPoint: surface - up * 40
            ))
            var bubbles = glass
            bubbles.clip(to: water)
            for index in 0..<4 {
                let rise = (time * 13 + Double(index) * 11).truncatingRemainder(dividingBy: 40)
                let bubble = CGPoint(x: -6 + Double(index) * 4, y: 21 - rise)
                bubbles.stroke(Circle().path(in: CGRect(center: bubble, radius: 1 + Double(index % 2) * 0.5)),
                               with: .color(.white.opacity(0.7)), lineWidth: 0.7)
            }
        }

        // The label, with a droplet on it.
        glass.fill(Path(CGRect(x: -13, y: 1, width: 26, height: 12)), with: .color(label))
        glass.stroke(Path(CGRect(x: -13, y: 1, width: 26, height: 12)), with: .color(ink.color.opacity(0.35)), lineWidth: 0.8)
        glass.fill(DropShape().path(in: CGRect(x: -2.6, y: 3, width: 5.2, height: 7.2)), with: .color(.white.opacity(0.92)))

        // Glass: a long highlight down the near side and a thin inner rim.
        glass.fill(Capsule().path(in: CGRect(x: -9.4, y: -10, width: 2.6, height: 9)), with: .color(.white.opacity(0.75)))
        glass.fill(Capsule().path(in: CGRect(x: -9.4, y: 14, width: 2.6, height: 6)), with: .color(.white.opacity(0.55)))
        glass.stroke(shape, with: .color(.white.opacity(0.55)), lineWidth: 1.6)

        guard capped else { return }
        let cap = RoundedRectangle(cornerRadius: 2.6, style: .continuous).path(in: CGRect(x: -7.6, y: -33, width: 15.2, height: 9.5))
        ink.turned(by: angle).paint(cap, self.cap, in: bottle)
        for ridge in stride(from: -4.5, through: 4.5, by: 3) {
            var line = Path()
            line.move(to: CGPoint(x: ridge, y: -31))
            line.addLine(to: CGPoint(x: ridge, y: -25.5))
            ink.crease(line, in: bottle, width: 0.8, opacity: 0.35)
        }
    }
}

// MARK: - Geometry

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }

    var length: CGFloat { (x * x + y * y).squareRoot() }

    var normalized: CGPoint {
        let length = length
        return length > 0 ? CGPoint(x: x / length, y: y / length) : .zero
    }

    /// Turned clockwise (on screen) by `degrees` around the origin.
    func rotated(by degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: x * cos(radians) - y * sin(radians), y: x * sin(radians) + y * cos(radians))
    }

    /// Angle of this vector in degrees, 0 = right, clockwise on screen.
    var degrees: Double { atan2(y, x) * 180 / .pi }
}

extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    init(center: CGPoint, width: CGFloat, height: CGFloat) {
        self.init(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}

extension Path {
    /// Turned clockwise (on screen) by `degrees` around `pivot`.
    func rotated(by degrees: Double, around pivot: CGPoint) -> Path {
        applying(
            CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -pivot.x, y: -pivot.y)
        )
    }
}
