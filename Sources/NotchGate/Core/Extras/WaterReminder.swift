import Foundation
import Observation

/// The water-reminder extra: every few minutes a little bot (or Spidey, Batman or the
/// dev) drops out of the notch holding a bottle and asks you to drink. Counts glasses per day.
@MainActor
@Observable
final class WaterReminder {
    enum State: Equatable {
        /// Tucked inside the notch, waiting for the next reminder.
        case away
        /// Hanging below the notch, asking you to drink.
        case asking
        /// You drank: a short celebration before it climbs back up.
        case drinking
        /// You snoozed: a yawn before it climbs back up.
        case snoozing
    }

    private enum Key {
        static let day = "water.day"
        static let glasses = "water.glasses"
    }

    let settings: AppSettings

    private(set) var state: State = .away
    /// When the bot next drops in; nil while the reminder is off.
    private(set) var nextReminder: Date?
    /// When the current reminder appeared; the bot grows impatient from here.
    private(set) var askedAt: Date?
    /// When the last glass was logged from the bot (drives the sip animation).
    private(set) var drankAt: Date?
    private(set) var glassesToday: Int
    /// Counts reminders so the bot doesn't open with the same line every time.
    private(set) var reminderCount = 0
    /// No keyboard or mouse input for a while: the bot naps instead of nagging.
    private(set) var isUserAway = false
    /// Who's hanging from the notch this time; picked from `settings.waterTheme` on each reminder.
    private(set) var character: WaterCharacter = .robot
    /// Dropped in from the Extras ▶ button: a demo that leaves today's count
    /// and the next reminder alone.
    private(set) var isPreview = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let idleSeconds: () -> TimeInterval
    @ObservationIgnored private var generator: any RandomNumberGenerator
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var exit: Task<Void, Never>?

    /// Reminders wait while nobody's at the Mac; there's no one to drink.
    static let awayAfter: TimeInterval = 120
    static let tickInterval: Duration = .seconds(5)
    /// Sip, cheer, then climb back into the notch.
    static let celebration: Duration = .milliseconds(2600)
    static let yawn: Duration = .milliseconds(1700)

    init(
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        idleSeconds: @escaping () -> TimeInterval = SystemIdle.seconds,
        generator: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.settings = settings
        self.defaults = defaults
        self.now = now
        self.idleSeconds = idleSeconds
        self.generator = generator
        let today = defaults.string(forKey: Key.day) == Self.dayStamp(now())
        glassesToday = today ? defaults.integer(forKey: Key.glasses) : 0
    }

    var goalReached: Bool { glassesToday >= settings.waterDailyGoal }

    func start() {
        if settings.waterReminder { schedule() }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self else { return }
                tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        exit?.cancel()
    }

    /// Checks the clock and whether anyone is at the Mac. Runs every few seconds.
    func tick() {
        rollOverDayIfNeeded()
        let away = idleSeconds() >= Self.awayAfter
        if away != isUserAway { isUserAway = away }
        guard settings.waterReminder, state == .away, !isUserAway,
              let next = nextReminder, now() >= next else { return }
        remind()
    }

    // MARK: Settings

    func setEnabled(_ enabled: Bool) {
        settings.waterReminder = enabled
        guard enabled else {
            exit?.cancel()
            state = .away
            askedAt = nil
            isPreview = false
            nextReminder = nil
            return
        }
        schedule()
    }

    /// Changing the interval restarts the countdown from now.
    func setInterval(minutes: Int) {
        settings.waterReminderMinutes = minutes
        if state == .away { schedule() }
    }

    // MARK: Intents

    /// Drops the bot in right away.
    func remind() {
        guard state == .away else { return }
        exit?.cancel()
        reminderCount += 1
        character = settings.waterTheme.pick(using: &generator)
        askedAt = now()
        isPreview = false
        state = .asking
        if settings.playSound { SoundPlayer.play(.water, volume: 0.3) }
    }

    /// The Extras ▶ button: drops the buddy in now, even with the reminder
    /// off. Drinking or snoozing then plays out without logging a glass or
    /// moving the next reminder. Pressed again while it hangs there, it swaps
    /// in a fresh pick (so a new Buddy choice shows straight away).
    func preview() {
        switch state {
        case .away:
            remind()
            isPreview = true
        case .asking:
            reminderCount += 1
            character = settings.waterTheme.pick(using: &generator)
            askedAt = now()
        case .drinking, .snoozing:
            break
        }
    }

    /// Logs a glass. From the bot it sips and celebrates; from the activity
    /// panel it just counts and restarts the countdown.
    func drink() {
        guard state != .drinking else { return }
        if isPreview {
            guard state == .asking else { return }
            if settings.playSound { SoundPlayer.play(.sip, volume: 0.3) }
            drankAt = now()
            state = .drinking
            leave(after: Self.celebration)
            return
        }
        rollOverDayIfNeeded()
        glassesToday += 1
        defaults.set(glassesToday, forKey: Key.glasses)
        schedule()
        if settings.playSound {
            glassesToday == settings.waterDailyGoal ? SoundPlayer.play(.goal, volume: 0.3) : SoundPlayer.play(.sip, volume: 0.3)
        }
        guard state == .asking else { return }
        drankAt = now()
        state = .drinking
        leave(after: Self.celebration)
    }

    func snooze() {
        guard state == .asking else { return }
        if !isPreview {
            nextReminder = settings.waterReminder ? now().addingTimeInterval(TimeInterval(settings.waterSnoozeMinutes * 60)) : nil
        }
        state = .snoozing
        leave(after: Self.yawn)
    }

    /// Sends the bot home without counting a glass; the regular countdown restarts.
    func skip() {
        guard state == .asking else { return }
        if !isPreview { schedule() }
        state = .away
        askedAt = nil
        isPreview = false
    }

    // MARK: Private

    private func schedule() {
        nextReminder = settings.waterReminder
            ? now().addingTimeInterval(TimeInterval(max(1, settings.waterReminderMinutes) * 60))
            : nil
    }

    private func leave(after delay: Duration) {
        exit?.cancel()
        exit = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            state = .away
            askedAt = nil
            isPreview = false
        }
    }

    private func rollOverDayIfNeeded() {
        let today = Self.dayStamp(now())
        guard defaults.string(forKey: Key.day) != today else { return }
        defaults.set(today, forKey: Key.day)
        defaults.set(0, forKey: Key.glasses)
        if glassesToday != 0 { glassesToday = 0 }
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// "45 min", "1 hr", "1 hr 30 min".
    static func format(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(rest) min"
        }
    }
}
