import AppKit
@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import NotchGate

@Suite("Notch Voice shortcut")
struct VoiceShortcutTests {
    @Test func savesAndLoadsOneOrTwoKeys() {
        let single = VoiceShortcut(keys: [.rightOption])
        #expect(single?.storageValue == "rightOption")
        #expect(VoiceShortcut(storageValue: "rightOption") == single)

        let pair = VoiceShortcut(keys: [.leftOption, .leftControl])
        #expect(pair?.storageValue == "leftControl+leftOption")
        #expect(VoiceShortcut(storageValue: "leftOption+leftControl") == pair)
    }

    @Test func rejectsNoKeysTooManyKeysAndUnknownNames() {
        #expect(VoiceShortcut(keys: []) == nil)
        #expect(VoiceShortcut(keys: [.leftControl, .leftOption, .leftShift]) == nil)
        #expect(VoiceShortcut(storageValue: "") == nil)
        #expect(VoiceShortcut(storageValue: "rightOption+hyper") == nil)
    }

    @Test func showsKeycapsInMacOrder() {
        let shortcut = VoiceShortcut(keys: [.rightCommand, .leftControl])
        #expect(shortcut?.keycaps == ["Left ⌃", "Right ⌘"])
        #expect(shortcut?.spokenName == "Left Control + Right Command")
        #expect(VoiceShortcut(keys: [.function])?.keycaps == ["fn"])
    }

    @Test func tellsLeftFromRightInEventFlags() {
        // Right ⌥ down: the device-independent ⌥ bit plus the right-hand device bit.
        let rightOption = NSEvent.ModifierFlags.option.rawValue | 0x40
        #expect(ModifierKey.held(in: rightOption) == [.rightOption])
        let leftControlAndOption = NSEvent.ModifierFlags([.control, .option]).rawValue | 0x01 | 0x20
        #expect(ModifierKey.held(in: leftControlAndOption) == [.leftControl, .leftOption])
        #expect(ModifierKey.held(in: NSEvent.ModifierFlags.function.rawValue) == [.function])
        #expect(ModifierKey.held(in: 0).isEmpty)
    }

    @Test func onlyFnAloneNeedsTheGlobeKeyWarning() {
        #expect(VoiceShortcut(keys: [.function])?.usesFunctionKeyAlone == true)
        #expect(VoiceShortcut(keys: [.function, .leftControl])?.usesFunctionKeyAlone == false)
        #expect(VoiceShortcut.default.usesFunctionKeyAlone == false)
    }
}

@Suite("Notch Voice hold detection")
struct HoldDetectorTests {
    private var detector = HoldDetector(shortcut: .default)

    @Test mutating func holdingTheKeyAloneStartsAndReleasingEnds() {
        #expect(detector.modifiersChanged(to: [.rightOption]) == .startArmTimer)
        #expect(detector.armTimerFired() == .begin)
        #expect(detector.phase == .active)
        #expect(detector.modifiersChanged(to: []) == .end)
        #expect(detector.phase == .idle)
    }

    @Test mutating func aShortcutLikeOptionArrowNeverStartsDictation() {
        _ = detector.modifiersChanged(to: [.rightOption])
        #expect(detector.keyPressed() == .cancelArmTimer)
        #expect(detector.armTimerFired() == nil)
        #expect(detector.phase == .blocked)
        // Still held: stays blocked. Released: ready again.
        #expect(detector.modifiersChanged(to: [.rightOption]) == nil)
        #expect(detector.modifiersChanged(to: []) == nil)
        #expect(detector.phase == .idle)
        #expect(detector.modifiersChanged(to: [.rightOption]) == .startArmTimer)
    }

    @Test mutating func optionClickNeverStartsDictation() {
        _ = detector.modifiersChanged(to: [.rightOption])
        #expect(detector.mousePressed() == .cancelArmTimer)
        #expect(detector.armTimerFired() == nil)
    }

    @Test mutating func typingWhileListeningThrowsTheRecordingAway() {
        _ = detector.modifiersChanged(to: [.rightOption])
        _ = detector.armTimerFired()
        #expect(detector.keyPressed() == .cancel)
        #expect(detector.modifiersChanged(to: []) == nil)
    }

    @Test mutating func addingAnotherModifierIsAShortcutNotDictation() {
        _ = detector.modifiersChanged(to: [.rightOption])
        #expect(detector.modifiersChanged(to: [.rightOption, .leftShift]) == .cancelArmTimer)
        #expect(detector.phase == .blocked)
        // Letting go of only the extra key doesn't re-arm.
        #expect(detector.modifiersChanged(to: [.rightOption]) == nil)
    }

    @Test mutating func theOtherSideDoesNothing() {
        #expect(detector.modifiersChanged(to: [.leftOption]) == nil)
        #expect(detector.phase == .idle)
    }

    @Test mutating func clickingTheMouseWhileListeningKeepsListening() {
        _ = detector.modifiersChanged(to: [.rightOption])
        _ = detector.armTimerFired()
        #expect(detector.mousePressed() == nil)
        #expect(detector.phase == .active)
    }

    @Test func twoKeyShortcutsArmOnceBothAreDown() {
        var detector = HoldDetector(shortcut: VoiceShortcut(keys: [.leftControl, .leftOption])!)
        #expect(detector.modifiersChanged(to: [.leftControl]) == nil)
        #expect(detector.modifiersChanged(to: [.leftControl, .leftOption]) == .startArmTimer)
        #expect(detector.armTimerFired() == .begin)
        // Letting go of either key finishes.
        #expect(detector.modifiersChanged(to: [.leftOption]) == .end)
    }
}

@Suite("Notch Voice settings")
@MainActor
struct VoiceSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "voice-\(UUID())") ?? .standard
    }

    @Test func isOffUntilSwitchedOn() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(!settings.voiceEnabled)
        #expect(settings.voiceShortcut == .default)
        #expect(settings.voiceLanguage == VoiceLanguage.automatic)
    }

    @Test func remembersTheChosenShortcut() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.voiceShortcut = VoiceShortcut(keys: [.leftControl, .leftOption])!
        settings.voiceLanguage = "en-IN"
        #expect(AppSettings(defaults: defaults).voiceShortcut.storageValue == "leftControl+leftOption")
        #expect(AppSettings(defaults: defaults).voiceLanguage == "en-IN")
    }

    @Test func aDamagedSavedShortcutFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set("banana", forKey: "voiceShortcut")
        #expect(AppSettings(defaults: defaults).voiceShortcut == .default)
    }

    @Test func automaticLanguageFollowsTheMacsEnglish() {
        #expect(VoiceLanguage.locale(for: "", current: Locale(identifier: "en_IN")).identifier == "en-IN")
        #expect(VoiceLanguage.locale(for: "", current: Locale(identifier: "en_GB")).identifier == "en-GB")
        // Not English: US English.
        #expect(VoiceLanguage.locale(for: "", current: Locale(identifier: "fr_FR")).identifier == "en-US")
        #expect(VoiceLanguage.locale(for: "en-AU").identifier == "en-AU")
    }

    @Test func aNewDictationIsIdleAndOff() {
        let voice = VoiceDictation(settings: AppSettings(defaults: makeDefaults()))
        #expect(voice.phase == .idle)
        #expect(voice.readiness == .off)
        #expect(voice.levels.count == VoiceDictation.waveformBars)
    }
}

@Suite("Notch Voice typing")
@MainActor
struct TextInserterPlanTests {
    @Test func typesIntoTextFieldsAndRestoresTheClipboard() {
        #expect(TextInserter.plan(trusted: true, focus: .text, secureInput: false) == .paste(restoreClipboard: true))
    }

    @Test func typesEvenWhenTheAppHidesItsField() {
        // Cursor, VS Code and other Electron apps often report nothing or a plain group.
        #expect(TextInserter.plan(trusted: true, focus: .other, secureInput: false) == .paste(restoreClipboard: false))
        #expect(TextInserter.plan(trusted: true, focus: .none, secureInput: false) == .paste(restoreClipboard: false))
    }

    @Test func neverTypesIntoPasswordFields() {
        #expect(TextInserter.plan(trusted: true, focus: .secure, secureInput: true) == .copy(.secureInput))
        #expect(TextInserter.plan(trusted: true, focus: .other, secureInput: true) == .copy(.secureInput))
        // A real text field while another app holds secure input is still typed into.
        #expect(TextInserter.plan(trusted: true, focus: .text, secureInput: true) == .paste(restoreClipboard: true))
    }

    @Test func withoutAccessibilityTheWordsAreCopied() {
        #expect(TextInserter.plan(trusted: false, focus: .text, secureInput: false) == .copy(.accessibilityOff))
    }
}

@Suite("Notch Voice audio")
struct VoiceAudioTests {
    /// macOS calls the microphone tap on an audio thread. A tap closure isolated to the
    /// main actor traps there (SIGTRAP), so this runs the real tap through an offline engine.
    @MainActor
    @Test func theMicrophoneTapRunsOnTheAudioThread() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let received = Counter()
        let capture = AudioCapture(
            onBuffer: { _ in received.add(buffers: 1) },
            onLevels: { levels in received.add(levels: levels.count) },
            onInterrupted: {}
        )
        capture.installTap(on: engine.mainMixerNode, format: nil)
        try engine.start()
        defer { engine.stop() }

        let tone = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        tone.frameLength = 48_000
        for index in 0..<Int(tone.frameLength) { tone.floatChannelData![0][index] = 0.2 * sin(Float(index) / 8) }
        player.scheduleBuffer(tone, completionHandler: nil)
        player.play()
        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        for _ in 0..<12 { _ = try engine.renderOffline(4096, to: output) }

        // Tap buffers arrive asynchronously from the audio thread.
        for _ in 0..<40 where received.buffers == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(received.buffers > 0)
        #expect(received.levels > 0)
    }

    @Test func loudnessStaysBetweenZeroAndOne() {
        #expect(AudioCapture.normalized(rms: 0) == 0)
        #expect(AudioCapture.normalized(rms: 0.000_01) == 0)
        #expect(AudioCapture.normalized(rms: 1) == 1)
        let quiet = AudioCapture.normalized(rms: 0.005)
        let loud = AudioCapture.normalized(rms: 0.1)
        #expect(quiet > 0 && quiet < loud && loud < 1)
    }

    @Test func liveTextKeepsSettledPhrasesAndTheLatestGuess() {
        var live = LiveTranscript()
        live.apply("Can you", isFinal: false)
        live.apply("Can you refactor this", isFinal: false)
        #expect(live.text == "Can you refactor this")
        live.apply("Can you refactor this function?", isFinal: true)
        #expect(live.text == "Can you refactor this function?")
        // The next phrase's guesses come without the settled one, often with a leading space.
        live.apply(" then add", isFinal: false)
        #expect(live.text == "Can you refactor this function? then add")
        live.apply(" then add a test", isFinal: false)
        #expect(live.text == "Can you refactor this function? then add a test")
    }

    @Test func joinsRecognizedSegmentsWithSingleSpaces() {
        guard #available(macOS 26, *) else { return }
        #expect(AnalyzerSession.joined(["Can you refactor", "  this function?", "Thanks. "]) == "Can you refactor this function? Thanks.")
        #expect(AnalyzerSession.joined([]) == "")
    }
}

/// Counts calls from any thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffersSeen = 0
    private var levelsSeen = 0

    var buffers: Int { lock.withLock { buffersSeen } }
    var levels: Int { lock.withLock { levelsSeen } }

    func add(buffers: Int = 0, levels: Int = 0) {
        lock.withLock {
            buffersSeen += buffers
            levelsSeen += levels
        }
    }
}
