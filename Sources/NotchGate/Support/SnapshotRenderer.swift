import AppKit
import SwiftUI

/// Development aid: `NotchGate --snapshot <dir>` renders every demo card to
/// PNG offscreen (no Screen Recording permission needed), then exits.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for sample in DemoRequests.Sample.allCases {
            render(sample, to: directory.appendingPathComponent("\(sample.id.lowercased().replacingOccurrences(of: " ", with: "-")).png"))
        }
        return true
    }

    private static func render(_ sample: DemoRequests.Sample, to url: URL) {
        let store = RequestStore()
        let model = IslandViewModel(store: store, settings: AppSettings(defaults: UserDefaults(suiteName: "snapshot") ?? .standard))
        model.notch = NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            notchSize: CGSize(width: 185, height: 32),
            hasNotch: true
        )
        store.enqueue(DemoRequests.make(sample), responder: DemoResponder())

        let size = Theme.Metrics.canvasSize
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.backgroundColor = NSColor(white: 0.18, alpha: 1) // Stand-in for a desktop.
        let hosting = NSHostingView(rootView: IslandRootView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()

        // Let layout, measurement passes and the expand spring settle.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("snapshot: \(url.path)")
    }
}
