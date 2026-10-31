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
        // Text typed and left: the island closed, the 💬 chip carries a dot.
        render(to: directory.appendingPathComponent("activity-draft.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.prompts.texts.set("Also add a test for the timeout path", for: "demo-docs")
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-quick-settings-info.png"), infoTip: "Claude's questions") { model in
            model.activity.load(DemoActivity.sessions())
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
            // The usage card starts closed (its gauge button opens it); show both widgets.
            model.settings.usageCardShown = true
            model.settings.showQuickSettingsInNotch = false
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
        for range in InsightsRange.allCases {
            render(to: directory.appendingPathComponent("activity-insights-\(range.title).png")) { model in
                model.activity.load(DemoActivity.sessions())
                model.settings.insightsCardShown = true
                model.settings.insightsRange = range
                model.settings.sessionCardShown = false
                model.settings.showQuickSettingsInNotch = false
                model.insights.showPreview(DemoActivity.insights())
                model.showActivityNow()
            }
        }
        // Everything in the header at once: the island widens so every word fits, never wraps.
        for updating in [false, true] {
            let name = updating ? "activity-header-updating.png" : "activity-header-crowded.png"
            render(to: directory.appendingPathComponent(name)) { model in
                model.activity.load(DemoActivity.sessions())
                model.settings.autoAllowPermissions = true
                model.settings.nowPlaying = true
                model.settings.insightsWidget = true
                model.settings.showQuickSettingsInNotch = false
                model.updates.showPreview(UpdateInfo(latestSHA: "abc1234", commits: [], aheadBy: 1), updating: updating)
                model.showActivityNow()
            }
        }
        // Claude Code's default 30 days of transcripts, seen over a year.
        render(to: directory.appendingPathComponent("activity-insights-short-history.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.settings.insightsCardShown = true
            model.settings.insightsRange = .year
            model.settings.sessionCardShown = false
            model.settings.showQuickSettingsInNotch = false
            model.insights.showPreview(DemoActivity.insights(days: 30))
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("activity-insights-hover.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.settings.insightsCardShown = true
            model.settings.insightsRange = .day
            model.settings.sessionCardShown = false
            model.settings.showQuickSettingsInNotch = false
            model.insights.showPreview(DemoActivity.insights())
            model.previewInsightsBar = 21
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
        // A session working with the island closed: the Live badge beside the notch.
        render(to: directory.appendingPathComponent("live-closed.png")) { model in
            model.activity.load(DemoActivity.sessions())
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
        render(to: directory.appendingPathComponent("water-spidey.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .spidey
            model.water.remind()
        }
        render(to: directory.appendingPathComponent("water-spidey-hover.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .spidey
            model.water.remind()
            model.setHoveringWaterBot(true)
        }
        render(to: directory.appendingPathComponent("water-spidey-drinking.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .spidey
            model.water.remind()
            model.water.drink()
        }
        render(to: directory.appendingPathComponent("water-batman.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .batman
            model.water.remind()
        }
        render(to: directory.appendingPathComponent("water-batman-hover.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .batman
            model.water.remind()
            model.setHoveringWaterBot(true)
        }
        render(to: directory.appendingPathComponent("water-batman-drinking.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .batman
            model.water.remind()
            model.water.drink()
        }
        render(to: directory.appendingPathComponent("water-dev.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .developer
            model.water.remind()
        }
        render(to: directory.appendingPathComponent("water-dev-hover.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .developer
            model.water.remind()
            model.setHoveringWaterBot(true)
        }
        render(to: directory.appendingPathComponent("water-dev-drinking.png")) { model in
            model.settings.playSound = false
            model.settings.waterTheme = .developer
            model.water.remind()
            model.water.drink()
        }
        render(to: directory.appendingPathComponent("now-playing.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.settings.nowPlaying = true
            model.settings.showQuickSettingsInNotch = false
            model.settings.sessionCardShown = false
            model.nowPlaying.showPreview(sampleTrack(), artwork: sampleArtwork())
            model.showActivityNow()
        }
        // Everything open at once: taller than the window, so the panel scrolls.
        render(to: directory.appendingPathComponent("activity-everything.png")) { model in
            model.activity.load(DemoActivity.sessions())
            model.settings.nowPlaying = true
            model.settings.usageCardShown = true
            model.settings.toolsCardShown = true
            model.settings.resumeCardShown = true
            model.nowPlaying.showPreview(sampleTrack(), artwork: sampleArtwork())
            model.usage.showPreview(nil)
            model.session.showPreview([])
            model.resume.showPreview(DemoActivity.pastSessions())
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("now-playing-video.png")) { model in
            model.settings.nowPlaying = true
            model.settings.showQuickSettingsInNotch = false
            model.settings.sessionCardShown = false
            model.nowPlaying.showPreview(NowPlayingTrack(
                title: "Building a notch app in SwiftUI, from first sketch to shipping",
                artist: "Indie Dev Diaries", appName: "Google Chrome", appBundleID: "com.google.Chrome",
                duration: 1_394, elapsed: 312, sampledAt: Date(), isPlaying: false,
                commands: [0, 1, 2, 3, 24]
            ), artwork: sampleArtwork(hues: (.systemTeal, .systemIndigo)))
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("now-playing-empty.png")) { model in
            model.settings.nowPlaying = true
            model.settings.showQuickSettingsInNotch = false
            model.settings.sessionCardShown = false
            model.nowPlaying.showPreview(nil)
            model.showActivityNow()
        }
        render(to: directory.appendingPathComponent("now-playing-closed.png")) { model in
            model.settings.nowPlaying = true
            model.nowPlaying.showPreview(sampleTrack(), artwork: sampleArtwork())
        }
        renderWaterBotMoods(to: directory.appendingPathComponent("water-bot-moods.png"))
        renderWaterBotMoods(of: .spidey, to: directory.appendingPathComponent("water-spidey-moods.png"))
        renderWaterBotMoods(of: .batman, to: directory.appendingPathComponent("water-batman-moods.png"))
        renderWaterBotMoods(of: .developer, to: directory.appendingPathComponent("water-dev-moods.png"))
        renderVoicePills(to: directory.appendingPathComponent("voice-pill.png"))
        // Notch Voice switched on, on its own settings so the user's stay untouched.
        let voiceDefaults = UserDefaults(suiteName: "snapshot-voice") ?? .standard
        voiceDefaults.removePersistentDomain(forName: "snapshot-voice")
        let voiceSettings = AppSettings(defaults: voiceDefaults)
        voiceSettings.voiceEnabled = true
        // An empty models folder, so the snapshot never shows (or touches) the user's downloads.
        let modelsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-speech-models", isDirectory: true)
        renderMenu(
            VoiceSection(settings: voiceSettings, voice: VoiceDictation(settings: voiceSettings, models: SpeechModelStore(folder: modelsFolder))).padding(16),
            to: directory.appendingPathComponent("menu-voice.png")
        )
        // Whistle downloaded and typing (its files sparse, so nothing is really written),
        // Shruti part-way through its download.
        let models = SpeechModelStore(folder: modelsFolder)
        for file in SpeechModel.whistle.files {
            let url = models.folder(for: .whistle).appendingPathComponent(file.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            try? FileHandle(forWritingTo: url).truncate(atOffset: UInt64(file.size))
        }
        models.refresh()
        models.showPreview(.downloading(progress: 0.43), for: .shruti)
        voiceSettings.voiceModel = SpeechModel.whistle.id
        renderMenu(
            VoiceSection(settings: voiceSettings, voice: VoiceDictation(settings: voiceSettings, models: models)).padding(16),
            to: directory.appendingPathComponent("menu-voice-models.png")
        )
        // The pointer resting on Shruti's row: who it suits.
        renderMenu(
            VoiceSection(settings: voiceSettings, voice: VoiceDictation(settings: voiceSettings, models: models))
                .padding(16)
                .infoTipHost()
                .environment(\.infoTipPreview, SpeechModelRow.whyPreview(.shruti)),
            to: directory.appendingPathComponent("menu-voice-why.png")
        )
        voiceSettings.voiceModel = SpeechModel.appleID
        try? FileManager.default.removeItem(at: modelsFolder)
        let coordinator = AppCoordinator()
        coordinator.updates.showPreview(UpdateInfo(latestSHA: "abc1234", commits: [
            UpdateCommit(sha: "abc1234", title: "Type notch prompts into Claude Code as real user prompts"),
            UpdateCommit(sha: "def5678", title: "Keep the island open after clicking buttons"),
        ], aheadBy: 2))
        renderMenu(MenuBarContentView(coordinator: coordinator), to: directory.appendingPathComponent("menu.png"))
        renderMenu(
            MenuBarContentView(coordinator: coordinator, sectionsMaxHeight: .infinity).environment(\.expandsAllMenuSections, true),
            to: directory.appendingPathComponent("menu-expanded.png")
        )
        // An ⓘ bubble open, as when hovering it.
        renderMenu(
            MenuBarContentView(coordinator: coordinator)
                .environment(\.expandsAllMenuSections, true)
                .environment(\.infoTipPreview, "Auto-allow permissions"),
            to: directory.appendingPathComponent("menu-info.png")
        )
        return true
    }

    /// A made-up album, mid-song, in a player that takes every command.
    private static func sampleTrack() -> NowPlayingTrack {
        NowPlayingTrack(
            title: "Golden Hour Drive (Extended Sunset Mix)", artist: "Lumen & The Tides", album: "Neon Coast",
            appName: "Music", appBundleID: "com.apple.Music", duration: 247, elapsed: 83, sampledAt: Date(),
            isPlaying: true, shuffleMode: 1, repeatMode: 2, commands: [0, 1, 2, 4, 5, 6, 7, 24, 25, 26]
        )
    }

    /// Stand-in cover art: a sunset gradient with a sun and horizon lines.
    private static func sampleArtwork(hues: (NSColor, NSColor) = (.systemOrange, .systemPink)) -> NSImage {
        NSImage(size: CGSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(starting: hues.0, ending: hues.1)?.draw(in: rect, angle: -90)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: 95, y: 110, width: 110, height: 110)).fill()
            NSColor.black.withAlphaComponent(0.35).setFill()
            for (index, y) in stride(from: 40.0, to: 130.0, by: 18.0).enumerated() {
                NSBezierPath(rect: CGRect(x: 0, y: y, width: 300, height: 4 + Double(index))).fill()
            }
            return true
        }
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

    /// Every state of the Notch Voice pill, top to bottom.
    private static func renderVoicePills(to url: URL) {
        let bars = Double(VoiceDictation.waveformBars)
        let speech = (0..<VoiceDictation.waveformBars).map { index -> Float in
            let position = Double(index)
            let swell: Double = abs(sin(position / 2.4))
            let rise: Double = 0.5 + 0.5 * position / bars
            return Float(0.2 + 0.6 * swell * rise)
        }
        let listening = VoiceDictation.Phase.listening(since: Date().addingTimeInterval(-4))
        let pills: [(VoiceDictation.Phase, String)] = [
            (listening, ""),
            // The words as they're heard, short and long.
            (listening, "Can you refactor this function"),
            (listening, "Can you refactor this function so it returns early when the user is not logged in and then add a test"),
            (.transcribing, ""), (.inserted(words: 12), ""),
            (.copied(.accessibilityOff), ""), (.nothingHeard, ""), (.failed(.microphoneDenied), ""),
        ]
        let canvas = CGSize(width: 600, height: CGFloat(pills.count) * 56 + 56)
        SnapshotExport.write(
            SnapshotBackdrop(showsMenuBar: false) {
                VStack(spacing: 18) {
                    ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                        VoicePill(phase: pill.0, levels: speech, liveText: pill.1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            canvas: canvas, to: url, settle: 0.6
        )
    }

    /// Every face the water bot (or Spidey, Batman or the dev) can make, side by side.
    private static func renderWaterBotMoods(of character: WaterCharacter = .robot, to url: URL) {
        let moods = WaterBotMood.allCases
        let size = WaterBotFigure.size
        let canvas = CGSize(width: CGFloat(moods.count) * (size.width + 12) + 48, height: size.height + 64)
        SnapshotExport.write(
            SnapshotBackdrop(showsMenuBar: false) {
                HStack(spacing: 12) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { index, mood in
                        let time = 0.9 + Double(index) * 0.37, sip: CGFloat = mood == .delighted ? 1 : 0
                        let waterLevel: CGFloat = mood == .delighted ? 0.4 : 0.8
                        switch character {
                        case .robot: WaterBotFigure(mood: mood, time: time, sip: sip, waterLevel: waterLevel)
                        // Late enough that the arrival bounce has settled.
                        case .spidey: SpideyFigure(mood: mood, time: time + 3, sip: sip, waterLevel: waterLevel)
                        case .batman: BatFigure(mood: mood, time: time, sip: sip, waterLevel: waterLevel)
                        // Late enough that the bounce on the cable has settled.
                        case .developer: DevFigure(mood: mood, time: time + 3, sip: sip, waterLevel: waterLevel)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            },
            canvas: canvas, to: url, settle: 0.6
        )
    }

    /// One island state under a menu bar, cropped tight around the island.
    private static func render(to url: URL, infoTip: String? = nil, configure: (IslandViewModel) -> Void) {
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
            SnapshotBackdrop { IslandRootView(model: model).environment(\.infoTipPreview, infoTip) },
            canvas: Theme.Metrics.canvasSize, to: url
        ) {
            var island = model.islandFrame
            guard !island.isEmpty else { return nil }
            if model.showsWaterBot, !model.waterBotFrame.isEmpty { island = island.union(model.waterBotFrame) }
            return CGRect(x: island.minX - 70, y: 0, width: island.width + 140, height: island.maxY + 64)
        }
    }
}
