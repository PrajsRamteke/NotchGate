import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let playSound = "playSound"
        static let autoExpand = "autoExpand"
        static let showNotices = "showNotices"
        static let replyFromNotch = "replyFromNotch"
        static let activityOnHover = "showActivityOnHover"
        static let autoAllow = "autoAllowPermissions"
        static let askForRisky = "askForRiskyCommands"
        static let questionMode = "questionMode"
        static let quickSettingsInNotch = "showQuickSettingsInNotch"
        static let notchPermissions = "notchPermissions"
        static let notchFileEdits = "notchFileEdits"
        static let notchPlans = "notchPlans"
        static let checkForUpdates = "checkForUpdates"
        static let waterReminder = "waterReminder"
        static let waterReminderMinutes = "waterReminderMinutes"
        static let waterSnoozeMinutes = "waterSnoozeMinutes"
        static let waterDailyGoal = "waterDailyGoal"
        static let waterTheme = "waterTheme"
        static let nowPlaying = "nowPlaying"
        static let nowPlayingCardShown = "nowPlayingCardShown"
        static let nowPlayingInClosedNotch = "nowPlayingInClosedNotch"
        static let usageWidget = "widgetUsage"
        static let usageCardShown = "usageCardShown"
        static let sessionWidget = "widgetSession"
        static let sessionCardShown = "sessionCardShown"
        static let toolsWidget = "widgetTools"
        static let toolsCardShown = "toolsCardShown"
        static let resumeWidget = "widgetResume"
        static let resumeCardShown = "resumeCardShown"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Soft chime when a request arrives.
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.playSound) } }

    /// Expand the full card on arrival (otherwise show a compact peek first).
    var autoExpand: Bool { didSet { defaults.set(autoExpand, forKey: Key.autoExpand) } }

    /// Show transient notices such as "Claude finished".
    var showNotices: Bool { didSet { defaults.set(showNotices, forKey: Key.showNotices) } }

    /// When Claude finishes, offer an input field to send it the next prompt.
    /// Non-blocking: Claude finishes normally and wakes only if you send.
    var replyFromNotch: Bool { didSet { defaults.set(replyFromNotch, forKey: Key.replyFromNotch) } }

    /// Hovering the idle notch reveals live progress for every session.
    var showActivityOnHover: Bool { didSet { defaults.set(showActivityOnHover, forKey: Key.activityOnHover) } }

    // MARK: What the notch handles (off = leave it to the terminal)

    /// Tool permission prompts (commands, web, MCP…), except file edits.
    var notchPermissions: Bool { didSet { defaults.set(notchPermissions, forKey: Key.notchPermissions) } }

    /// Permission prompts for Edit / Write / MultiEdit / NotebookEdit.
    var notchFileEdits: Bool { didSet { defaults.set(notchFileEdits, forKey: Key.notchFileEdits) } }

    /// Plan approval (ExitPlanMode).
    var notchPlans: Bool { didSet { defaults.set(notchPlans, forKey: Key.notchPlans) } }

    /// Look for a newer NotchGate on GitHub every few hours.
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Key.checkForUpdates) } }

    /// Approve permission prompts automatically, without showing a card.
    var autoAllowPermissions: Bool { didSet { defaults.set(autoAllowPermissions, forKey: Key.autoAllow) } }

    /// With auto-allow on, still ask for destructive commands (see `RiskPolicy`).
    var askForRiskyCommands: Bool { didSet { defaults.set(askForRiskyCommands, forKey: Key.askForRisky) } }

    /// Where Claude's questions go: the notch, the terminal (default), or nowhere.
    var questionMode: QuestionMode { didSet { defaults.set(questionMode.rawValue, forKey: Key.questionMode) } }

    /// Show the quick-settings box in the hover panel. Hidden with its ✕;
    /// the same controls always remain in the menu bar.
    var showQuickSettingsInNotch: Bool {
        didSet { defaults.set(showQuickSettingsInNotch, forKey: Key.quickSettingsInNotch) }
    }

    // MARK: Extras (notch features unrelated to Claude)

    /// A bot drops out of the notch with a bottle every few minutes (see `WaterReminder`).
    var waterReminder: Bool { didSet { defaults.set(waterReminder, forKey: Key.waterReminder) } }

    /// Minutes between water reminders.
    var waterReminderMinutes: Int { didSet { defaults.set(waterReminderMinutes, forKey: Key.waterReminderMinutes) } }

    /// How long "Snooze" puts the bot back to sleep.
    var waterSnoozeMinutes: Int { didSet { defaults.set(waterSnoozeMinutes, forKey: Key.waterSnoozeMinutes) } }

    /// Glasses to drink per day.
    var waterDailyGoal: Int { didSet { defaults.set(waterDailyGoal, forKey: Key.waterDailyGoal) } }

    /// Who brings the bottle: the robot, Spidey, or either at random.
    var waterTheme: WaterTheme { didSet { defaults.set(waterTheme.rawValue, forKey: Key.waterTheme) } }

    /// What's playing on the Mac (Music, Spotify, a browser tab…) with its controls (see `NowPlayingMonitor`).
    var nowPlaying: Bool { didSet { defaults.set(nowPlaying, forKey: Key.nowPlaying) } }

    /// Whether the Now Playing card is open in the hover panel. Toggled from its header button.
    var nowPlayingCardShown: Bool { didSet { defaults.set(nowPlayingCardShown, forKey: Key.nowPlayingCardShown) } }

    /// While something plays, the closed notch widens a little to show its artwork and a live equalizer.
    var nowPlayingInClosedNotch: Bool {
        didSet { defaults.set(nowPlayingInClosedNotch, forKey: Key.nowPlayingInClosedNotch) }
    }

    // MARK: Widgets (glanceable info in the hover panel)

    /// Plan limits (5-hour and weekly) in the notch (see `UsageMonitor`).
    var usageWidget: Bool { didSet { defaults.set(usageWidget, forKey: Key.usageWidget) } }

    /// Whether the usage card is open in the hover panel. Toggled from the
    /// gauge button beside the Activity header, so it stays out of the way by default.
    var usageCardShown: Bool { didSet { defaults.set(usageCardShown, forKey: Key.usageCardShown) } }

    /// Model, context fill, cost and git branch of the latest session (see `SessionMonitor`).
    var sessionWidget: Bool { didSet { defaults.set(sessionWidget, forKey: Key.sessionWidget) } }

    /// Whether the session card is open in the hover panel. Toggled from the chip button beside the usage gauge.
    var sessionCardShown: Bool { didSet { defaults.set(sessionCardShown, forKey: Key.sessionCardShown) } }

    /// Which tools each session has called, and when (see `ToolUsage`).
    var toolsWidget: Bool { didSet { defaults.set(toolsWidget, forKey: Key.toolsWidget) } }

    /// Whether the tools card is open in the hover panel. Toggled from its header button.
    var toolsCardShown: Bool { didSet { defaults.set(toolsCardShown, forKey: Key.toolsCardShown) } }

    /// Resume a recent session or start a new one (see `ResumeMonitor`).
    var resumeWidget: Bool { didSet { defaults.set(resumeWidget, forKey: Key.resumeWidget) } }

    /// Whether the resume card is open in the hover panel. Toggled from its header button.
    var resumeCardShown: Bool { didSet { defaults.set(resumeCardShown, forKey: Key.resumeCardShown) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.playSound: true,
            Key.autoExpand: true,
            Key.showNotices: false,
            Key.replyFromNotch: false,
            Key.activityOnHover: true,
            Key.autoAllow: false,
            Key.askForRisky: true,
            Key.questionMode: QuestionMode.terminal.rawValue,
            Key.notchPermissions: true,
            Key.notchFileEdits: false,
            Key.notchPlans: false,
            Key.checkForUpdates: true,
            Key.quickSettingsInNotch: true,
            Key.waterReminder: true,
            Key.waterReminderMinutes: 15,
            Key.waterSnoozeMinutes: 10,
            Key.waterDailyGoal: 8,
            Key.waterTheme: WaterTheme.robot.rawValue,
            Key.nowPlaying: false,
            Key.nowPlayingCardShown: true,
            Key.nowPlayingInClosedNotch: true,
            Key.usageWidget: true,
            Key.usageCardShown: false,
            Key.sessionWidget: true,
            Key.sessionCardShown: true,
            Key.toolsWidget: true,
            Key.toolsCardShown: false,
            Key.resumeWidget: true,
            Key.resumeCardShown: true,
        ])
        playSound = defaults.bool(forKey: Key.playSound)
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        showNotices = defaults.bool(forKey: Key.showNotices)
        replyFromNotch = defaults.bool(forKey: Key.replyFromNotch)
        showActivityOnHover = defaults.bool(forKey: Key.activityOnHover)
        autoAllowPermissions = defaults.bool(forKey: Key.autoAllow)
        askForRiskyCommands = defaults.bool(forKey: Key.askForRisky)
        showQuickSettingsInNotch = defaults.bool(forKey: Key.quickSettingsInNotch)
        questionMode = QuestionMode(rawValue: defaults.string(forKey: Key.questionMode) ?? "") ?? .terminal
        notchPermissions = defaults.bool(forKey: Key.notchPermissions)
        notchFileEdits = defaults.bool(forKey: Key.notchFileEdits)
        notchPlans = defaults.bool(forKey: Key.notchPlans)
        checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)
        waterReminder = defaults.bool(forKey: Key.waterReminder)
        waterReminderMinutes = defaults.integer(forKey: Key.waterReminderMinutes)
        waterSnoozeMinutes = defaults.integer(forKey: Key.waterSnoozeMinutes)
        waterDailyGoal = defaults.integer(forKey: Key.waterDailyGoal)
        waterTheme = WaterTheme(rawValue: defaults.string(forKey: Key.waterTheme) ?? "") ?? .robot
        nowPlaying = defaults.bool(forKey: Key.nowPlaying)
        nowPlayingCardShown = defaults.bool(forKey: Key.nowPlayingCardShown)
        nowPlayingInClosedNotch = defaults.bool(forKey: Key.nowPlayingInClosedNotch)
        usageWidget = defaults.bool(forKey: Key.usageWidget)
        usageCardShown = defaults.bool(forKey: Key.usageCardShown)
        sessionWidget = defaults.bool(forKey: Key.sessionWidget)
        sessionCardShown = defaults.bool(forKey: Key.sessionCardShown)
        toolsWidget = defaults.bool(forKey: Key.toolsWidget)
        toolsCardShown = defaults.bool(forKey: Key.toolsCardShown)
        resumeWidget = defaults.bool(forKey: Key.resumeWidget)
        resumeCardShown = defaults.bool(forKey: Key.resumeCardShown)
    }

    var routerOptions: RequestRouter.Options {
        RequestRouter.Options(
            replyFromNotch: replyFromNotch,
            showNotices: showNotices,
            autoAllowPermissions: autoAllowPermissions,
            askForRiskyCommands: askForRiskyCommands,
            questionMode: questionMode,
            showPermissions: notchPermissions,
            showFileEdits: notchFileEdits,
            showPlans: notchPlans
        )
    }
}
