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
        render(to: directory.appendingPathComponent("activity-reply.png")) { model in
            model.activity.load(DemoActivity.sessions())
            let finished = DemoRequests.make(.completion, sessionID: "demo-docs")
            model.store.enqueue(finished, responder: DemoResponder(), parked: true)
            model.initialComposerSession = "demo-docs"
            model.showActivityNow()
        }
        let coordinator = AppCoordinator()
        coordinator.updates.showPreview(UpdateInfo(latestSHA: "abc1234", commits: [
            UpdateCommit(sha: "abc1234", title: "Type notch prompts into Claude Code as real user prompts"),
            UpdateCommit(sha: "def5678", title: "Keep the island open after clicking buttons"),
        ], aheadBy: 2))
        renderMenu(MenuBarContentView(coordinator: coordinator), to: directory.appendingPathComponent("menu.png"))
        return true
    }

    /// The menu-bar popover floating on the wallpaper, like it appears on screen.
    private static func renderMenu<V: View>(_ menu: V, to url: URL) {
        let panel = menu
            .frame(width: 320)
            .fixedSize()
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        let fitted = NSHostingView(rootView: panel).fittingSize
        let canvas = CGSize(width: fitted.width + 80, height: fitted.height + 80)
        SnapshotExport.write(
            SnapshotBackdrop(showsMenuBar: false) { panel.frame(maxWidth: .infinity, maxHeight: .infinity) },
            canvas: canvas, to: url, settle: 0.8
        )
    }

    /// One island state under a menu bar, cropped tight around the island.
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

        SnapshotExport.write(
            SnapshotBackdrop { IslandRootView(model: model) },
            canvas: Theme.Metrics.canvasSize, to: url
        ) {
            let island = model.islandFrame
            guard !island.isEmpty else { return nil }
            return CGRect(x: island.minX - 70, y: 0, width: island.width + 140, height: island.maxY + 64)
        }
    }
}
