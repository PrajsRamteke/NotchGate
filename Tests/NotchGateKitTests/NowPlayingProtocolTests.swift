import Foundation
import Testing
@testable import NotchGateKit

@Suite("Now Playing protocol")
struct NowPlayingProtocolTests {
    @Test(arguments: [
        NowPlayingCommand.play, .pause, .togglePlayPause, .nextTrack, .previousTrack,
        .seek(to: 83.5), .setShuffleMode(3), .setRepeatMode(2), .advanceShuffleMode, .advanceRepeatMode, .refresh,
    ])
    func commandsSurviveTheTripThroughALine(_ command: NowPlayingCommand) {
        #expect(NowPlayingCommand(line: command.line) == command)
        #expect(NowPlayingCommand(line: command.line + "\n") == command)
    }

    @Test func malformedCommandsAreIgnored() {
        #expect(NowPlayingCommand(line: "") == nil)
        #expect(NowPlayingCommand(line: "rewind") == nil)
        #expect(NowPlayingCommand(line: "seek") == nil)
        #expect(NowPlayingCommand(line: "seek soon") == nil)
        #expect(NowPlayingCommand(line: "seek nan") == nil)
        #expect(NowPlayingCommand(line: "shuffle on") == nil)
    }

    @Test func seekingNeverGoesBeforeTheStart() {
        #expect(NowPlayingCommand(line: "seek -12") == .seek(to: 0))
    }

    @Test func messagesRoundTripThroughJSON() throws {
        let message = NowPlayingMessage(
            bundleID: "com.spotify.client", appName: "Spotify", title: "Song", artist: "Band",
            duration: 200, elapsed: 12.5, timestamp: 1_800_000_000, rate: 1, isPlaying: true,
            shuffleMode: 3, repeatMode: 1, commands: [0, 1, 2, 4, 5], artworkKey: "abc", artwork: "AAEC"
        )
        let decoded = try JSONDecoder().decode(NowPlayingMessage.self, from: JSONEncoder().encode(message))
        #expect(decoded == message)
    }

    @Test func aMinimalMessageDecodes() throws {
        let decoded = try JSONDecoder().decode(NowPlayingMessage.self, from: Data(#"{"isPlaying":false,"commands":[]}"#.utf8))
        #expect(decoded.title == nil)
        #expect(!decoded.isPlaying)
    }
}
