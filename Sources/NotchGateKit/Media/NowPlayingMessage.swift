import Foundation

/// What the media helper (`NotchGateMedia`, running inside `/usr/bin/perl`)
/// reports on each change: one JSON object per line on its stdout.
public struct NowPlayingMessage: Codable, Equatable, Sendable {
    /// The app that owns the player, e.g. `com.spotify.client` or `com.google.Chrome`.
    public var bundleID: String?
    /// For players running in a helper process (a browser tab), the app to bring forward.
    public var parentBundleID: String?
    public var appName: String?

    public var title: String?
    public var artist: String?
    public var album: String?

    public var duration: Double?
    /// Position at `timestamp`; while playing it advances by `rate` per second.
    public var elapsed: Double?
    /// When `elapsed` was sampled, in seconds since 1970.
    public var timestamp: Double?
    public var rate: Double?
    public var isPlaying: Bool

    /// MediaRemote's modes: shuffle 1 off, 2 albums, 3 songs; repeat 1 off, 2 one, 3 all.
    public var shuffleMode: Int?
    public var repeatMode: Int?
    /// Raw `MediaRemoteCommand` values the player accepts right now.
    public var commands: [Int]

    /// Identifies the artwork; `nil` when the player has none.
    public var artworkKey: String?
    /// Base64 image data, sent only when `artworkKey` changes.
    public var artwork: String?

    public init(
        bundleID: String? = nil, parentBundleID: String? = nil, appName: String? = nil,
        title: String? = nil, artist: String? = nil, album: String? = nil,
        duration: Double? = nil, elapsed: Double? = nil, timestamp: Double? = nil, rate: Double? = nil,
        isPlaying: Bool = false, shuffleMode: Int? = nil, repeatMode: Int? = nil, commands: [Int] = [],
        artworkKey: String? = nil, artwork: String? = nil
    ) {
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.appName = appName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
        self.shuffleMode = shuffleMode
        self.repeatMode = repeatMode
        self.commands = commands
        self.artworkKey = artworkKey
        self.artwork = artwork
    }
}

/// MediaRemote's command numbers (`MRMediaRemoteCommand`), as players report
/// them in `NowPlayingMessage.commands`.
public enum MediaRemoteCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case advanceShuffleMode = 6
    case advanceRepeatMode = 7
    case seekToPlaybackPosition = 24
    case changeRepeatMode = 25
    case changeShuffleMode = 26
}

/// What the app asks the media helper to do: one line on its stdin.
public enum NowPlayingCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(to: Double)
    case setShuffleMode(Int)
    case setRepeatMode(Int)
    /// Step to the player's next shuffle / repeat mode, for players that only take that.
    case advanceShuffleMode
    case advanceRepeatMode
    /// Report the current state again, artwork included.
    case refresh

    public var line: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .togglePlayPause: return "toggle"
        case .nextTrack: return "next"
        case .previousTrack: return "previous"
        case .seek(let seconds): return "seek \(seconds)"
        case .setShuffleMode(let mode): return "shuffle \(mode)"
        case .setRepeatMode(let mode): return "repeat \(mode)"
        case .advanceShuffleMode: return "shuffle-next"
        case .advanceRepeatMode: return "repeat-next"
        case .refresh: return "refresh"
        }
    }

    public init?(line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return nil }
        let argument = parts.count > 1 ? parts[1] : nil
        switch verb {
        case "play": self = .play
        case "pause": self = .pause
        case "toggle": self = .togglePlayPause
        case "next": self = .nextTrack
        case "previous": self = .previousTrack
        case "refresh": self = .refresh
        case "shuffle-next": self = .advanceShuffleMode
        case "repeat-next": self = .advanceRepeatMode
        case "seek":
            guard let seconds = argument.flatMap(Double.init), seconds.isFinite else { return nil }
            self = .seek(to: max(0, seconds))
        case "shuffle":
            guard let mode = argument.flatMap(Int.init) else { return nil }
            self = .setShuffleMode(mode)
        case "repeat":
            guard let mode = argument.flatMap(Int.init) else { return nil }
            self = .setRepeatMode(mode)
        default: return nil
        }
    }
}
