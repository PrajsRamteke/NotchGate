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

    @Test func theChosenCharacterDropsIn() {
        let (water, _, _) = make()
        water.settings.waterTheme = .spidey
        water.remind()
        #expect(water.character == .spidey)

        water.skip()
        water.settings.waterTheme = .batman
        water.remind()
        #expect(water.character == .batman)

        water.skip()
        water.settings.waterTheme = .robot
        water.remind()
        #expect(water.character == .robot)
    }

    @Test func randomThemeMixesCharacters() {
        var generator = SplitMix(seed: 7)
        let picks = Set((0..<40).map { _ in WaterTheme.random.pick(using: &generator) })
        #expect(picks == Set(WaterCharacter.allCases))
    }

    @Test func themeIsRemembered() {
        let defaults = UserDefaults(suiteName: "water-theme-\(UUID())") ?? .standard
        AppSettings(defaults: defaults).waterTheme = .random
        #expect(AppSettings(defaults: defaults).waterTheme == .random)
    }

    @Test func previewDropsInWithoutCountingOrRescheduling() {
        let (water, world, _) = make()
        let next = water.nextReminder
        world.now += 60
        water.preview()
        #expect(water.state == .asking)
        #expect(water.isPreview)

        water.drink()
        #expect(water.state == .drinking)
        #expect(water.glassesToday == 0)
        #expect(water.nextReminder == next)
    }

    @Test func snoozingOrSkippingAPreviewKeepsTheSchedule() {
        let (water, world, _) = make()
        let next = water.nextReminder
        world.now += 60
        water.preview()
        water.snooze()
        #expect(water.state == .snoozing)
        #expect(water.nextReminder == next)

        let (other, otherWorld, _) = make()
        let otherNext = other.nextReminder
        otherWorld.now += 60
        other.preview()
        other.skip()
        #expect(other.state == .away)
        #expect(!other.isPreview)
        #expect(other.nextReminder == otherNext)
    }

    @Test func previewWorksWithTheReminderOff() {
        let (water, _, _) = make(enabled: false)
        water.preview()
        #expect(water.state == .asking)
        water.skip()
        #expect(water.state == .away)
        #expect(water.nextReminder == nil)
    }

    @Test func previewingAgainSwapsTheBuddy() {
        let (water, _, _) = make()
        water.settings.waterTheme = .spidey
        water.preview()
        water.settings.waterTheme = .batman
        water.preview()
        #expect(water.character == .batman)
        #expect(water.state == .asking)
    }

    @Test func aRealReminderIsNotAPreview() {
        let (water, _, _) = make()
        water.preview()
        water.skip()
        water.remind()
        #expect(!water.isPreview)
        water.drink()
        #expect(water.glassesToday == 1)
    }

    @Test func eachCharacterHasItsOwnLines() {
        let lines = WaterCharacter.allCases.map { WaterBotMood.cheerful.line(variant: 0, character: $0) }
        #expect(Set(lines).count == WaterCharacter.allCases.count)
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

/// A tiny seeded generator, so "random" is repeatable in tests.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
