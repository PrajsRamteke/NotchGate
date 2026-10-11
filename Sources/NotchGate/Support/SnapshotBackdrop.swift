import AppKit
import SwiftUI

/// Wallpaper and menu-bar strip behind snapshot renders, so README screenshots
/// look like the island on a real Mac rather than a card on white.
struct SnapshotBackdrop<Content: View>: View {
    var showsMenuBar = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x3B2A35), Color(hex: 0x2A2438), Color(hex: 0x1B2433)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Theme.Palette.clay.opacity(0.28), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 520
            )
            if showsMenuBar {
                Rectangle()
                    .fill(Color.black.opacity(0.32))
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5) }
            }
            content
        }
    }
}

enum SnapshotExport {
    /// Renders `view` offscreen at 2× and writes the region returned by `crop`
    /// (points, top-left origin; evaluated after layout settles) as PNG.
    @MainActor
    static func write<V: View>(
        _ view: V, canvas: CGSize, to url: URL, settle: TimeInterval = 1.2,
        crop: @MainActor () -> CGRect? = { nil }
    ) {
        let hosting = NSHostingView(rootView: view.frame(width: canvas.width, height: canvas.height))
        hosting.frame = CGRect(origin: .zero, size: canvas)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: canvas.width, height: canvas.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard var image = rep.cgImage else { return }

        if let crop = crop() {
            let scale = CGFloat(rep.pixelsWide) / canvas.width
            let pixels = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
                .intersection(CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
            if let cropped = image.cropping(to: pixels.integral) { image = cropped }
        }
        let output = NSBitmapImageRep(cgImage: image)
        try? output.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot: \(url.path)")
    }
}
