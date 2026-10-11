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
        static let holdForReply = "holdForReplyOnStop"
        static let replyWindow = "replyWindowSeconds"
        static let activityOnHover = "showActivityOnHover"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Soft chime when a request arrives.
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.playSound) } }

    /// Expand the full card on arrival (otherwise show a compact peek first).
    var autoExpand: Bool { didSet { defaults.set(autoExpand, forKey: Key.autoExpand) } }

    /// Show transient notices such as "Claude finished".
    var showNotices: Bool { didSet { defaults.set(showNotices, forKey: Key.showNotices) } }

    /// When Claude stops, briefly hold the session so you can reply from the notch.
    var holdForReplyOnStop: Bool { didSet { defaults.set(holdForReplyOnStop, forKey: Key.holdForReply) } }

    /// Hovering the idle notch reveals live progress for every session.
    var showActivityOnHover: Bool { didSet { defaults.set(showActivityOnHover, forKey: Key.activityOnHover) } }

    /// How long a "reply to continue" card stays open before releasing Claude.
    var replyWindowSeconds: Int { didSet { defaults.set(replyWindowSeconds, forKey: Key.replyWindow) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.playSound: true,
            Key.autoExpand: true,
            Key.showNotices: false,
            Key.holdForReply: false,
            Key.replyWindow: 45,
            Key.activityOnHover: true,
        ])
        playSound = defaults.bool(forKey: Key.playSound)
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        showNotices = defaults.bool(forKey: Key.showNotices)
        holdForReplyOnStop = defaults.bool(forKey: Key.holdForReply)
        replyWindowSeconds = defaults.integer(forKey: Key.replyWindow)
        showActivityOnHover = defaults.bool(forKey: Key.activityOnHover)
    }

    var routerOptions: RequestRouter.Options {
        RequestRouter.Options(
            holdForReplyOnStop: holdForReplyOnStop,
            replyWindow: TimeInterval(replyWindowSeconds),
            showNotices: showNotices
        )
    }
}
