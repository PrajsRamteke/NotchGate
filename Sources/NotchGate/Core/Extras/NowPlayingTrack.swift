import Foundation
import NotchGateKit

/// What's playing, as the Now Playing card shows it.
struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var appName: String?
    /// The app to bring forward: the browser for a web player, else the player itself.
    var appBundleID: String?
    var duration: TimeInterval?
    /// Position at `sampledAt`; while playing it moves on by `rate` each second.
    var elapsed: TimeInterval?
    var sampledAt: Date?
    var rate: Double = 1
    var isPlaying: Bool
    var shuffleMode: Int?
    var repeatMode: Int?
    /// Raw `MediaRemoteCommand` values the player takes right now.
    var commands: Set<Int> = []

    enum Repeat: Equatable {
        case off, one, all
    }

    /// `nil` when nothing is loaded in any player.
    init?(_ message: NowPlayingMessage) {
        guard let title = message.title.nonBlank else { return nil }
        self.title = title
        artist = message.artist.nonBlank
        album = message.album.nonBlank
        appName = message.appName.nonBlank
        appBundleID = message.parentBundleID.nonBlank ?? message.bundleID.nonBlank
        duration = message.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        elapsed = message.elapsed.flatMap { $0.isFinite ? max(0, $0) : nil }
        sampledAt = message.timestamp.map { Date(timeIntervalSince1970: $0) }
        rate = message.rate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
        isPlaying = message.isPlaying
        shuffleMode = message.shuffleMode
        repeatMode = message.repeatMode
        commands = Set(message.commands)
    }

    init(
        title: String, artist: String? = nil, album: String? = nil, appName: String? = nil, appBundleID: String? = nil,
        duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, sampledAt: Date? = nil, isPlaying: Bool = true,
        shuffleMode: Int? = nil, repeatMode: Int? = nil, commands: Set<Int> = []
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.appName = appName
        self.appBundleID = appBundleID
        self.duration = duration
        self.elapsed = elapsed
        self.sampledAt = sampledAt
        self.isPlaying = isPlaying
        self.shuffleMode = shuffleMode
        self.repeatMode = repeatMode
        self.commands = commands
    }

    /// The playhead at `now`, kept within the track.
    func position(at now: Date) -> TimeInterval? {
        guard var position = elapsed else { return nil }
        if isPlaying, let sampledAt { position += max(0, now.timeIntervalSince(sampledAt)) * rate }
        if let duration { position = min(position, duration) }
        return max(0, position)
    }

    /// Players re-report their position now and then, a little off from where
    /// the clock had it. While the same track plays on, small corrections are
    /// dropped so the time never ticks backwards; seeks still come through.
    func keepingPlayhead(of previous: NowPlayingTrack?, at now: Date) -> NowPlayingTrack {
        guard let previous, previous.title == title, previous.isPlaying, isPlaying, previous.rate == rate,
              let mine = position(at: now), let theirs = previous.position(at: now),
              abs(mine - theirs) < Self.driftTolerance else { return self }
        var kept = self
        kept.elapsed = previous.elapsed
        kept.sampledAt = previous.sampledAt
        return kept
    }

    static let driftTolerance: TimeInterval = 1.5

    /// A player that takes shuffle / repeat but never says which mode it's in
    /// keeps the one the card last set, so the button doesn't flick back off.
    func keepingModes(of previous: NowPlayingTrack?) -> NowPlayingTrack {
        guard let previous, previous.appBundleID == appBundleID else { return self }
        var kept = self
        kept.shuffleMode = shuffleMode ?? previous.shuffleMode
        kept.repeatMode = repeatMode ?? previous.repeatMode
        return kept
    }

    func progress(at now: Date) -> Double? {
        guard let duration, let position = position(at: now) else { return nil }
        return position / duration
    }

    /// Players that report no commands at all still take the basics.
    func supports(_ command: MediaRemoteCommand) -> Bool {
        guard !commands.isEmpty else {
            return [.play, .pause, .togglePlayPause, .nextTrack, .previousTrack].contains(command)
        }
        return commands.contains(command.rawValue)
    }

    var canSeek: Bool { duration != nil && elapsed != nil && supports(.seekToPlaybackPosition) }
    var canGoNext: Bool { supports(.nextTrack) }
    var canGoPrevious: Bool { supports(.previousTrack) }
    /// Offered whenever the player takes the command; a mode it never reports reads as off.
    var canShuffle: Bool { supports(.changeShuffleMode) || supports(.advanceShuffleMode) }
    var canRepeat: Bool { supports(.changeRepeatMode) || supports(.advanceRepeatMode) }

    var isShuffling: Bool { (shuffleMode ?? 1) > 1 }

    var repeating: Repeat {
        switch repeatMode {
        case 2: return .one
        case 3: return .all
        default: return .off
        }
    }

    /// "Artist — Album", skipping what's missing.
    var subtitle: String? {
        let parts = [artist, album].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// "0:42", "3:07", "1:02:09".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

private extension Optional where Wrapped == String {
    /// The trimmed string, or `nil` if there's nothing in it.
    var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
