import Foundation
import NotchGateKit

/// Entry point, called by `/usr/bin/perl` after it loads this library (see
/// `NowPlayingMonitor.hostScript`). Never returns: it reports the now-playing
/// state on stdout and runs commands from stdin until the app closes the pipe.
///
/// Why perl: since macOS 15.4, MediaRemote only answers Apple-signed processes,
/// so NotchGate can't read "now playing" itself. Perl is Apple-signed, and this
/// library runs inside it. The two arguments are perl's (interpreter, CV); unused.
@_cdecl("notchgate_media_run")
public func notchgateMediaRun(_: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?) {
    guard let bridge = MediaRemoteBridge() else {
        FileHandle.standardError.write(Data("NotchGateMedia: MediaRemote is unavailable\n".utf8))
        exit(1)
    }
    bridge.start()
    while let line = readLine() {
        bridge.perform(line)
    }
    // stdin closed: the app quit (or crashed); don't linger.
    exit(0)
}

/// Watches MediaRemote and writes a `NowPlayingMessage` line whenever anything changes.
final class MediaRemoteBridge: @unchecked Sendable {
    /// Players don't all post change notifications; a slow poll catches the rest.
    private static let pollInterval: DispatchTimeInterval = .seconds(3)
    /// Notifications arrive in bursts (track, artwork, rate…); one read covers them.
    private static let coalesceDelay: DispatchTimeInterval = .milliseconds(60)

    private let api: MediaRemoteAPI
    /// Everything below is only touched on this queue.
    private let queue = DispatchQueue(label: "app.notchgate.media", autoreleaseFrequency: .workItem)
    private let encoder = JSONEncoder()
    private var lastSent: NowPlayingMessage?
    private var sentArtworkKey: String?
    private var refreshScheduled = false
    private var observers: [NSObjectProtocol] = []
    private var timer: DispatchSourceTimer?

    init?() {
        guard let api = MediaRemoteAPI() else { return nil }
        self.api = api
    }

    func start() {
        api.registerForNotifications(queue)
        observers = api.notificationNames.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.scheduleRefresh()
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    func perform(_ line: String) {
        guard let command = NowPlayingCommand(line: line) else { return }
        queue.async { [self] in
            switch command {
            case .play: _ = api.send(.play)
            case .pause: _ = api.send(.pause)
            case .togglePlayPause: _ = api.send(.togglePlayPause)
            case .nextTrack: _ = api.send(.nextTrack)
            case .previousTrack: _ = api.send(.previousTrack)
            case .seek(let seconds): api.setElapsedTime(seconds)
            case .setShuffleMode(let mode): api.setShuffleMode(mode)
            case .setRepeatMode(let mode): api.setRepeatMode(mode)
            case .advanceShuffleMode: _ = api.send(.advanceShuffleMode)
            case .advanceRepeatMode: _ = api.send(.advanceRepeatMode)
            case .refresh:
                lastSent = nil
                sentArtworkKey = nil
            }
            scheduleRefresh()
        }
    }

    // MARK: Reading

    private func scheduleRefresh() {
        queue.async { [self] in
            guard !refreshScheduled else { return }
            refreshScheduled = true
            queue.asyncAfter(deadline: .now() + Self.coalesceDelay) { [self] in
                refreshScheduled = false
                refresh()
            }
        }
    }

    private func refresh() {
        api.nowPlayingInfo(on: queue) { [self] info in
            api.isPlaying(on: queue) { [self] playing in
                publish(info: info, isPlaying: playing)
            }
        }
    }

    private func publish(info: [String: Any], isPlaying: Bool) {
        let client = api.client()
        let commands = api.supportedCommands()
        let artworkData = info[Key.artworkData] as? Data
        let artworkKey = artworkData.flatMap { data in
            data.isEmpty ? nil : (info[Key.artworkIdentifier] as? String) ?? "\(data.count)-\(data.hashValue)"
        }
        var message = NowPlayingMessage(
            bundleID: client.bundleID,
            parentBundleID: client.parentBundleID,
            appName: client.name,
            title: info[Key.title] as? String,
            artist: info[Key.artist] as? String,
            album: info[Key.album] as? String,
            duration: (info[Key.duration] as? NSNumber)?.doubleValue,
            elapsed: (info[Key.elapsed] as? NSNumber)?.doubleValue,
            timestamp: (info[Key.timestamp] as? Date)?.timeIntervalSince1970,
            rate: (info[Key.rate] as? NSNumber)?.doubleValue,
            isPlaying: isPlaying,
            // The mode the shuffle / repeat commands carry first, then the now-playing info's.
            shuffleMode: commands.shuffleMode ?? MediaRemoteAPI.mode(Key.shuffleMode, in: info),
            repeatMode: commands.repeatMode ?? MediaRemoteAPI.mode(Key.repeatMode, in: info),
            commands: commands.supported,
            artworkKey: artworkKey
        )
        guard message != lastSent else { return }
        lastSent = message
        if artworkKey == nil {
            sentArtworkKey = nil
        } else if artworkKey != sentArtworkKey {
            message.artwork = artworkData?.base64EncodedString()
            sentArtworkKey = artworkKey
        }
        write(message)
    }

    private func write(_ message: NowPlayingMessage) {
        guard var line = try? encoder.encode(message) else { return }
        line.append(0x0A)
        FileHandle.standardOutput.write(line)
    }

    private enum Key {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsed = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let rate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let shuffleMode = "kMRMediaRemoteNowPlayingInfoShuffleMode"
        static let repeatMode = "kMRMediaRemoteNowPlayingInfoRepeatMode"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let artworkIdentifier = "kMRMediaRemoteNowPlayingInfoArtworkIdentifier"
    }
}
