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
        static let usageWidget = "widgetUsage"
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

    // MARK: Widgets (glanceable info in the hover panel)

    /// Plan limits (5-hour and weekly) in the notch (see `UsageMonitor`).
    var usageWidget: Bool { didSet { defaults.set(usageWidget, forKey: Key.usageWidget) } }

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
            Key.usageWidget: true,
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
        usageWidget = defaults.bool(forKey: Key.usageWidget)
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
