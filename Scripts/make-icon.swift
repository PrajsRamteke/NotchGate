// Draws NotchGate's app icon: the Claude spark on a dark, notch-shaped tile.
//
//   swift Scripts/make-icon.swift Resources/AppIcon.iconset
//   iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
//
// The spark geometry mirrors SparkShape in Sources/NotchGate/DesignSystem/ClaudeSpark.swift.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let clay = (r: 0.851, g: 0.467, b: 0.341)      // #D97757
let clayGlow = (r: 0.910, g: 0.569, b: 0.435)  // #E8916F
let ink = (r: 0.086, g: 0.086, b: 0.090)

func spark(in ctx: CGContext, center: CGPoint, radius: CGFloat) {
    let rays = 12
    let innerRatio: CGFloat = 0.16
    func point(_ origin: CGPoint, _ angle: CGFloat, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + cos(angle) * distance, y: origin.y + sin(angle) * distance)
    }
    ctx.beginPath()
    for index in 0..<rays {
        let angle = CGFloat(index) / CGFloat(rays) * .pi * 2 - .pi / 2
        let length = radius * (index % 2 == 0 ? 1.0 : 0.74)
        let halfWidth = radius * 0.085
        let inner = radius * innerRatio
        let tip = point(center, angle, length)
        let base = point(center, angle, inner)
        let normal = angle + .pi / 2
        let left = point(base, normal, halfWidth)
        let right = point(base, normal, -halfWidth)
        let shoulder = point(center, angle, inner + (length - inner) * 0.42)
        let c1 = point(shoulder, normal, halfWidth * 1.15)
        let c2 = point(shoulder, normal, -halfWidth * 1.15)
        ctx.move(to: left)
        ctx.addQuadCurve(to: tip, control: c1)
        ctx.addQuadCurve(to: right, control: c2)
        ctx.closePath()
    }
    ctx.setFillColor(CGColor(red: clay.r, green: clay.g, blue: clay.b, alpha: 1))
    ctx.fillPath()
    // Filled separately (not in the ray path) so the hub never punches holes in the rays.
    let hub = radius * innerRatio * 1.6
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
}

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    // Apple's icon grid: art sits inside an 824/1024 squircle-ish tile.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tileRadius = tile.width * 0.2237
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    // Background: near-black with a faint warm lift toward the top.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.16, green: 0.155, blue: 0.15, alpha: 1),
        CGColor(red: ink.r, green: ink.g, blue: ink.b, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: tile.maxY),
                           end: CGPoint(x: s / 2, y: tile.minY), options: [])

    // The notch: a black pill hanging from the top edge of the tile.
    let notchWidth = tile.width * 0.34
    let notchHeight = tile.height * 0.11
    let notch = CGRect(x: tile.midX - notchWidth / 2, y: tile.maxY - notchHeight,
                       width: notchWidth, height: notchHeight)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.addPath(CGPath(roundedRect: notch, cornerWidth: notchHeight / 2, cornerHeight: notchHeight / 2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Soft clay glow behind the spark, then the spark itself.
    let center = CGPoint(x: tile.midX, y: tile.midY - tile.height * 0.02)
    let radius = tile.width * 0.34
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: clayGlow.r, green: clayGlow.g, blue: clayGlow.b, alpha: 0.38),
        CGColor(red: clayGlow.r, green: clayGlow.g, blue: clayGlow.b, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius * 1.5, options: [])
    ctx.restoreGState()
    spark(in: ctx, center: center, radius: radius)

    return ctx.makeImage()
}

let sizes: [(name: String, px: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for entry in sizes {
    guard let image = render(size: entry.px) else { fatalError("render failed at \(entry.px)") }
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(entry.name).png") as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("can't write \(entry.name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("wrote \(sizes.count) PNGs to \(outDir)")
