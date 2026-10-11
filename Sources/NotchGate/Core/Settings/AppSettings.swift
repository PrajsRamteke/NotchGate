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
            Key.quickSettingsInNotch: true,
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
