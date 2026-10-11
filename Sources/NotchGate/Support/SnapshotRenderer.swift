import AppKit
import SwiftUI

/// Development aid: `NotchGate --snapshot <dir>` renders every demo card and
/// the activity panel to PNG offscreen (no Screen Recording permission needed).
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
            let name = sample.id.lowercased().replacingOccurrences(of: " ", with: "-")
            render(to: directory.appendingPathComponent("\(name).png")) { model in
                model.store.enqueue(DemoRequests.make(sample), responder: DemoResponder())
            }
        }
        render(to: directory.appendingPathComponent("activity.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.showActivityNow()
        }
        return true
    }

    private static func render(to url: URL, configure: (IslandViewModel) -> Void) {
        let model = IslandViewModel(
            store: RequestStore(),
            settings: AppSettings(defaults: UserDefaults(suiteName: "snapshot") ?? .standard),
            activity: ActivityTracker()
        )
        model.notch = NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            notchSize: CGSize(width: 185, height: 32),
            hasNotch: true
        )
        configure(model)

        let size = Theme.Metrics.canvasSize
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: IslandRootView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()

        // Let layout, measurement passes and the expand spring settle.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])?.write(to: url)
        window.orderOut(nil)
        print("snapshot: \(url.path)")
    }
}
