import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Now Playing")
@MainActor
struct NowPlayingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func message(
        title: String? = "Golden Hour", isPlaying: Bool = true, elapsed: Double? = 60, duration: Double? = 200,
        commands: [Int] = [0, 1, 2, 4, 5, 24]
    ) -> NowPlayingMessage {
        NowPlayingMessage(
            bundleID: "com.apple.WebKit.GPU", parentBundleID: "com.apple.Safari", appName: "Safari",
            title: title, artist: "Lumen", album: "  ", duration: duration, elapsed: elapsed,
            timestamp: start.timeIntervalSince1970, rate: isPlaying ? 1 : 0, isPlaying: isPlaying, commands: commands
        )
    }

    // MARK: Track

    @Test func nothingLoadedMeansNoTrack() {
        #expect(NowPlayingTrack(message(title: nil)) == nil)
        #expect(NowPlayingTrack(message(title: "   ")) == nil)
    }

    @Test func blankFieldsAreDroppedAndBrowsersOpenTheBrowser() throws {
        let track = try #require(NowPlayingTrack(message()))
        #expect(track.album == nil)
        #expect(track.subtitle == "Lumen")
        #expect(track.appBundleID == "com.apple.Safari")
    }

    @Test func thePlayheadMovesOnlyWhilePlaying() throws {
        let playing = try #require(NowPlayingTrack(message()))
        #expect(playing.position(at: start.addingTimeInterval(15)) == 75)
        #expect(playing.progress(at: start.addingTimeInterval(40)) == 0.5)
        // It never runs past the end.
        #expect(playing.position(at: start.addingTimeInterval(1_000)) == 200)

        let paused = try #require(NowPlayingTrack(message(isPlaying: false)))
        #expect(paused.position(at: start.addingTimeInterval(15)) == 60)
    }

    @Test func smallPositionCorrectionsDontMoveThePlayheadButSeeksDo() throws {
        let playing = try #require(NowPlayingTrack(message()))
        let now = start.addingTimeInterval(10)

        var drifted = playing
        drifted.elapsed = 69
        drifted.sampledAt = now
        #expect(drifted.keepingPlayhead(of: playing, at: now).position(at: now) == 70)

        var sought = playing
        sought.elapsed = 150
        sought.sampledAt = now
        #expect(sought.keepingPlayhead(of: playing, at: now).position(at: now) == 150)

        var paused = drifted
        paused.isPlaying = false
        #expect(paused.keepingPlayhead(of: playing, at: now).position(at: now) == 69)
    }

    @Test func buttonsFollowWhatThePlayerSupports() throws {
        let single = try #require(NowPlayingTrack(message(commands: [0, 1, 2, 24])))
        #expect(!single.canGoNext)
        #expect(!single.canGoPrevious)
        #expect(single.canSeek)
        #expect(!single.canShuffle)

        let live = try #require(NowPlayingTrack(message(duration: nil)))
        #expect(!live.canSeek)

        // A player that lists nothing still gets the basics.
        let quiet = try #require(NowPlayingTrack(message(commands: [])))
        #expect(quiet.canGoNext)
        #expect(!quiet.canSeek)
    }

    @Test func shuffleAndRepeatShowOnlyForPlayersThatTakeThem() throws {
        // A browser tab: play, pause, skip, seek.
        let browser = try #require(NowPlayingTrack(message(commands: [0, 1, 2, 3, 4, 5, 24])))
        #expect(!browser.canShuffle)
        #expect(!browser.canRepeat)

        // Takes them without saying which mode it's in: offered, reading as off.
        var track = try #require(NowPlayingTrack(message(commands: [2, 6, 7])))
        #expect(track.canShuffle)
        #expect(!track.isShuffling)
        #expect(track.canRepeat)
        #expect(track.repeating == .off)
        track.shuffleMode = 3
        track.repeatMode = 2
        #expect(track.isShuffling)
        #expect(track.repeating == .one)

        let music = try #require(NowPlayingTrack(message(commands: [0, 1, 2, 25, 26])))
        #expect(music.canShuffle)
        #expect(music.canRepeat)
    }

    @Test func aModeTheCardSetSurvivesAPlayerThatNeverReportsOne() throws {
        var set = try #require(NowPlayingTrack(message(commands: [2, 25, 26])))
        set.shuffleMode = 3
        set.repeatMode = 2
        let report = try #require(NowPlayingTrack(message(commands: [2, 25, 26])))
        #expect(report.keepingModes(of: set).isShuffling)
        #expect(report.keepingModes(of: set).repeating == .one)

        // What the player does report wins.
        var reported = report
        reported.shuffleMode = 1
        #expect(!reported.keepingModes(of: set).isShuffling)

        // A different player starts fresh.
        var other = report
        other.appBundleID = "com.apple.Music"
        #expect(!other.keepingModes(of: set).isShuffling)
    }

    @Test func clockFormatsMinutesAndHours() {
        #expect(NowPlayingTrack.clock(0) == "0:00")
        #expect(NowPlayingTrack.clock(83.9) == "1:23")
        #expect(NowPlayingTrack.clock(3_729) == "1:02:09")
        #expect(NowPlayingTrack.clock(.nan) == "0:00")
    }

    // MARK: Closed notch

    private func makeModel(closedNotch: Bool = true) -> IslandViewModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "now-playing-\(UUID())") ?? .standard)
        settings.nowPlaying = true
        settings.nowPlayingInClosedNotch = closedNotch
        return IslandViewModel(store: RequestStore(), settings: settings, activity: ActivityTracker())
    }

    @Test func musicPlayingWidensTheClosedNotch() throws {
        let model = makeModel()
        #expect(model.presentation == .hidden)

        model.nowPlaying.showPreview(try #require(NowPlayingTrack(message())))
        #expect(model.presentation == .peek)

        model.nowPlaying.showPreview(try #require(NowPlayingTrack(message(isPlaying: false))))
        #expect(model.presentation == .hidden)
    }

    @Test func theClosedNotchStaysPlainWhenTurnedOff() throws {
        let model = makeModel(closedNotch: false)
        model.nowPlaying.showPreview(try #require(NowPlayingTrack(message())))
        #expect(model.presentation == .hidden)
    }

    @Test func claudeTakesPrecedenceOverMusic() throws {
        let model = makeModel()
        model.nowPlaying.showPreview(try #require(NowPlayingTrack(message())))
        let session = SessionInfo(id: "s1", cwd: "/tmp/app", claudePID: 1)
        model.store.post(Notice(session: session, title: "Claude needs you", message: nil, tone: .attention))
        #expect(!model.showsNowPlayingPeek)
    }

    @Test func hoveringTheMusicPeekStillWaitsForIntent() throws {
        let model = makeModel()
        model.nowPlaying.showPreview(try #require(NowPlayingTrack(message())))
        model.setHovering(true)
        // The hover-intent delay hasn't passed: a sweep across the menu bar doesn't open it.
        #expect(model.presentation == .peek)
    }
}
