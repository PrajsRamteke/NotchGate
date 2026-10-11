import AppKit
import NotchGateKit
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
        render(to: directory.appendingPathComponent("activity-drop.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.setDraggingImages(true)
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-images.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.prompts.drafts.add(sampleImages(), to: "demo-docs")
            model.initialComposerSession = "demo-docs"
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-usage.png")) { model in
            model.activity.load(DemoActivity.sessions())
            let now = Date()
            model.usage.showPreview(UsageSnapshot(
                fiveHour: .init(usedPercentage: 23.5, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                sevenDay: .init(usedPercentage: 81.2, resetsAt: now.addingTimeInterval(3 * 86_400)),
                updatedAt: now.addingTimeInterval(-3 * 60)
            ))
            model.session.showPreview([
                SessionSnapshot(
                    sessionID: "demo-api", directory: "/Users/demo/checkout-api", model: "Opus",
                    contextPercent: 62.4, contextSize: 200_000, costUSD: 3.27,
                    branch: "feature/refund-webhooks", updatedAt: now.addingTimeInterval(-60)
                ),
                SessionSnapshot(
                    sessionID: "demo-web", directory: "/Users/demo/dashboard", model: "Sonnet",
                    contextPercent: 91, contextSize: 1_000_000, costUSD: 0.84,
                    branch: "main", updatedAt: now.addingTimeInterval(-40)
                ),
            ])
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-tools-resume.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.settings.usageWidget = false
            model.settings.sessionWidget = false
            model.settings.toolsCardShown = true
            model.settings.resumeCardShown = true
            model.settings.showQuickSettingsInNotch = false
            model.resume.showPreview(DemoActivity.pastSessions())
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-resume-empty.png")) { model in
            model.settings.toolsCardShown = true
            model.settings.resumeCardShown = true
            model.resume.showPreview([])
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-usage-waiting.png")) { model in
            model.usage.showPreview(nil)
            model.session.showPreview([])
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("water-reminder.png")) { model in
            model.settings.playSound = false
            model.water.remind()
        }
        render(to: directory.appendingPathComponent("water-reminder-hover.png")) { model in
            model.settings.playSound = false
            model.water.remind()
            model.setHoveringWaterBot(true)
        }
        render(to: directory.appendingPathComponent("water-drinking.png")) { model in
            model.settings.playSound = false
            model.water.remind()
            model.water.drink()
        }
        renderWaterBotMoods(to: directory.appendingPathComponent("water-bot-moods.png"))
        let coordinator = AppCoordinator()
        coordinator.updates.showPreview(UpdateInfo(latestSHA: "abc1234", commits: [
            UpdateCommit(sha: "abc1234", title: "Type notch prompts into Claude Code as real user prompts"),
            UpdateCommit(sha: "def5678", title: "Keep the island open after clicking buttons"),
        ], aheadBy: 2))
        renderMenu(MenuBarContentView(coordinator: coordinator), to: directory.appendingPathComponent("menu.png"))
        return true
    }

    /// Two stand-in "screenshots" for the attachment strip.
    private static func sampleImages() -> [ImageAttachment] {
        let palettes: [(NSColor, NSColor)] = [(.systemOrange, .systemPink), (.systemTeal, .systemIndigo)]
        return palettes.compactMap { top, bottom in
            let image = NSImage(size: CGSize(width: 320, height: 200), flipped: false) { rect in
                NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -60)
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: CGRect(x: 30, y: 120, width: 180, height: 22), xRadius: 6, yRadius: 6).fill()
                NSBezierPath(roundedRect: CGRect(x: 30, y: 80, width: 240, height: 14), xRadius: 5, yRadius: 5).fill()
                return true
            }
            return ImageIntake.importImage(image)
        }
    }

    /// The menu-bar popover floating on the wallpaper, like it appears on screen.
    private static func renderMenu<V: View>(_ menu: V, to url: URL) {
        let panel = menu
            .frame(width: 320)
            .fixedSize()
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        // Measure in a window after layout settles: the menu's scroll area sizes
        // itself from a measurement that only arrives after the first pass.
        let probe = NSHostingView(rootView: panel)
        let probeWindow = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 400),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        probeWindow.contentView = probe
        probeWindow.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let fitted = probe.fittingSize
        probeWindow.orderOut(nil)
        let canvas = CGSize(width: fitted.width + 80, height: fitted.height + 80)
        SnapshotExport.write(
            SnapshotBackdrop(showsMenuBar: false) { panel.frame(maxWidth: .infinity, maxHeight: .infinity) },
            canvas: canvas, to: url, settle: 0.8
        )
    }

    /// Every face the water bot can make, side by side.
    private static func renderWaterBotMoods(to url: URL) {
        let moods = WaterBotMood.allCases
        let size = WaterBotFigure.size
        let canvas = CGSize(width: CGFloat(moods.count) * (size.width + 12) + 48, height: size.height + 64)
        SnapshotExport.write(
            SnapshotBackdrop(showsMenuBar: false) {
                HStack(spacing: 12) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { index, mood in
                        WaterBotFigure(mood: mood, time: 0.9 + Double(index) * 0.37, sip: mood == .delighted ? 1 : 0,
                                       waterLevel: mood == .delighted ? 0.4 : 0.8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            canvas: canvas, to: url, settle: 0.6
        )
    }

    /// One island state under a menu bar, cropped tight around the island.
    private static func render(to url: URL, configure: (IslandViewModel) -> Void) {
        // Each render starts from the default settings; one that changes them doesn't leak into the next.
        let defaults = UserDefaults(suiteName: "snapshot") ?? .standard
        defaults.removePersistentDomain(forName: "snapshot")
        let model = IslandViewModel(
            store: RequestStore(),
            settings: AppSettings(defaults: defaults),
            activity: ActivityTracker()
        )
        model.notch = NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            notchSize: CGSize(width: 185, height: 32),
            hasNotch: true
        )
        // The Resume card would list this Mac's real sessions; renders that want it show samples.
        model.settings.resumeCardShown = false
        configure(model)

        SnapshotExport.write(
            SnapshotBackdrop { IslandRootView(model: model) },
            canvas: Theme.Metrics.canvasSize, to: url
        ) {
            var island = model.islandFrame
            guard !island.isEmpty else { return nil }
            if model.showsWaterBot, !model.waterBotFrame.isEmpty { island = island.union(model.waterBotFrame) }
            return CGRect(x: island.minX - 70, y: 0, width: island.width + 140, height: island.maxY + 64)
        }
    }
}
