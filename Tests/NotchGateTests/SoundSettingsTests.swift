import AppKit
import Foundation
import Testing
@testable import NotchGate

@Suite("Sound settings")
@MainActor
struct SoundSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "sounds-\(UUID())") ?? .standard
    }

    @Test func defaultsKeepTheOriginalSounds() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.playSound)
        #expect(settings.attentionSound == .tink)
        #expect(settings.finishedSound == .pop)
    }

    @Test func pickedSoundsAreRemembered() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.attentionSound = .submarine
        settings.finishedSound = .none

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.attentionSound == .submarine)
        #expect(reloaded.finishedSound == .none)
    }

    @Test func anUnknownSavedSoundFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set("Kazoo", forKey: "attentionSound")
        #expect(AppSettings(defaults: defaults).attentionSound == .tink)
    }

    @Test func everyListedSoundShipsWithMacOS() {
        #expect(!AlertSound.sounds.contains(.none))
        for sound in AlertSound.sounds {
            #expect(NSSound(named: NSSound.Name(sound.rawValue)) != nil, "\(sound.rawValue) is not a system sound")
        }
    }
}
