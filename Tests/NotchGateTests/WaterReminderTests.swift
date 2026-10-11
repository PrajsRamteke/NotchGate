import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Water reminder")
@MainActor
struct WaterReminderTests {
    /// A hand-cranked clock and idle timer.
    final class World {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var idle: TimeInterval = 0
    }

    private func make(enabled: Bool = true) -> (WaterReminder, World, UserDefaults) {
        let defaults = UserDefaults(suiteName: "water-\(UUID())") ?? .standard
        let settings = AppSettings(defaults: defaults)
        settings.playSound = false
        settings.waterReminderMinutes = 30
        let world = World()
        let water = WaterReminder(settings: settings, defaults: defaults, now: { world.now }, idleSeconds: { world.idle })
        water.setEnabled(enabled)
        return (water, world, defaults)
    }

    @Test func remindsOnceTheIntervalPasses() {
        let (water, world, _) = make()
        world.now += 29 * 60
        water.tick()
        #expect(water.state == .away)

        world.now += 61
        water.tick()
        #expect(water.state == .asking)
        #expect(water.askedAt == world.now)
    }

    @Test func staysQuietWhenOff() {
        let (water, world, _) = make(enabled: false)
        world.now += 24 * 3600
        water.tick()
        #expect(water.state == .away)
        #expect(water.nextReminder == nil)
    }

    @Test func waitsWhileTheUserIsAway() {
        let (water, world, _) = make()
        world.now += 31 * 60
        world.idle = 600
        water.tick()
        #expect(water.state == .away)
        #expect(water.isUserAway)

        world.idle = 2
        water.tick()
        #expect(water.state == .asking)
    }

    @Test func drinkingCountsAGlassAndRestartsTheCountdown() {
        let (water, world, defaults) = make()
        water.remind()
        world.now += 10
        water.drink()
        water.drink() // a double click mid-celebration counts once

        #expect(water.state == .drinking)
        #expect(water.glassesToday == 1)
        #expect(water.nextReminder == world.now + 30 * 60)
        #expect(defaults.integer(forKey: "water.glasses") == 1)
    }

    @Test func loggingFromThePanelDoesNotDropTheBot() {
        let (water, _, _) = make()
        water.drink()
        #expect(water.state == .away)
        #expect(water.glassesToday == 1)
    }

    @Test func snoozeUsesTheSnoozeLength() {
        let (water, world, _) = make()
        water.settings.waterSnoozeMinutes = 15
        water.remind()
        water.snooze()
        #expect(water.state == .snoozing)
        #expect(water.nextReminder == world.now + 15 * 60)
    }

    @Test func changingTheIntervalReschedules() {
        let (water, world, _) = make()
        world.now += 60
        water.setInterval(minutes: 45)
        #expect(water.nextReminder == world.now + 45 * 60)
    }

    @Test func glassesResetAtMidnight() {
        let (water, world, defaults) = make()
        water.drink()
        water.drink()
        #expect(water.glassesToday == 2)

        world.now += 24 * 3600
        water.tick()
        #expect(water.glassesToday == 0)
        #expect(defaults.integer(forKey: "water.glasses") == 0)
    }

    @Test func turningOffSendsTheBotHome() {
        let (water, _, _) = make()
        water.remind()
        water.setEnabled(false)
        #expect(water.state == .away)
        #expect(water.nextReminder == nil)
    }

    @Test func moodGrowsMoreInsistentTheLongerItWaits() {
        func mood(_ waited: TimeInterval, hovered: Bool = false, away: Bool = false) -> WaterBotMood {
            WaterBotMood.current(state: .asking, waited: waited, isHovered: hovered, isUserAway: away, isTickled: false)
        }
        #expect(mood(0) == .cheerful)
        #expect(mood(30) == .pleading)
        #expect(mood(90) == .thirsty)
        #expect(mood(90, hovered: true) == .excited)
        #expect(mood(5, away: true) == .sleepy)
    }

    @Test func botWaitsInsideTheNotchWhileACardIsOpen() {
        let defaults = UserDefaults(suiteName: "water-island-\(UUID())") ?? .standard
        let settings = AppSettings(defaults: defaults)
        settings.playSound = false
        let water = WaterReminder(settings: settings, defaults: defaults)
        let model = IslandViewModel(store: RequestStore(), settings: settings, activity: ActivityTracker(), water: water)
        water.remind()
        #expect(model.showsWaterBot)

        model.store.enqueue(ClaudeRequest(
            id: UUID(), event: .permissionRequest,
            session: SessionInfo(id: "s1", cwd: "/tmp/app", claudePID: 1),
            kind: .permission(ToolPermission(toolName: "Bash", input: .object([:]), suggestions: []))
        ), responder: DemoResponder())
        #expect(model.presentation == .expanded)
        #expect(!model.showsWaterBot)
    }

    @Test func formatsIntervals() {
        #expect(WaterReminder.format(minutes: 45) == "45 min")
        #expect(WaterReminder.format(minutes: 60) == "1 hr")
        #expect(WaterReminder.format(minutes: 90) == "1 hr 30 min")
    }
}
