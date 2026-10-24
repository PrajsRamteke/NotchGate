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
        #expect(!settings.voiceCleanupEnabled)
        #expect(settings.voiceCleanup == .openRouter)
    }

    @Test func switchingCleanUpOffKeepsTheChosenModel() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.voiceCleanup = .claude
        settings.voiceCleanupEnabled = true
        settings.voiceCleanupEnabled = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.voiceCleanupEnabled)
        #expect(reloaded.voiceCleanup == .claude)
    }

    @Test func earlierCleanUpChoicesCarryOver() {
        // The first builds had a Claude switch.
        let claudeSwitch = makeDefaults()
        claudeSwitch.set(true, forKey: "voicePolish")
        #expect(AppSettings(defaults: claudeSwitch).voiceCleanupEnabled)
        #expect(AppSettings(defaults: claudeSwitch).voiceCleanup == .claude)
        // Then a picker with an "Off" choice.
        let pickedOff = makeDefaults()
        pickedOff.set("off", forKey: "voiceCleanup")
        #expect(!AppSettings(defaults: pickedOff).voiceCleanupEnabled)
        #expect(AppSettings(defaults: pickedOff).voiceCleanup == .openRouter)
        let pickedOpenRouter = makeDefaults()
        pickedOpenRouter.set("openRouter", forKey: "voiceCleanup")
        #expect(AppSettings(defaults: pickedOpenRouter).voiceCleanupEnabled)
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

@Suite("Notch Voice clean-up")
struct TranscriptCleanupTests {
    private func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    // MARK: OpenRouter

    @Test func alwaysAsksOpenRoutersFreeRouter() throws {
        let body = try OpenRouterCleaner.requestBody(transcript: "use us in kuwait here", appName: "Cursor")
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "openrouter/free")
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        let user = try #require(messages.last?["content"] as? String)
        #expect(user.contains("<dictation>\nuse us in kuwait here\n</dictation>"))
        #expect(user.contains("Cursor"))
    }

    @Test func readsOpenRoutersReply() throws {
        let data = json(["choices": [["message": ["role": "assistant", "content": "Use async await here."], "finish_reason": "stop"]]])
        #expect(try OpenRouterCleaner.parse(data, status: 200) == "Use async await here.")
    }

    @Test func mapsOpenRouterErrors() {
        let error = { (code: Int, message: String) in self.json(["error": ["code": code, "message": message]]) }
        #expect(throws: CleanupError.invalidKey) { try OpenRouterCleaner.parse(error(401, "User not found."), status: 401) }
        #expect(throws: CleanupError.noCredit) { try OpenRouterCleaner.parse(error(402, "Insufficient credits"), status: 402) }
        #expect(throws: CleanupError.rateLimited) { try OpenRouterCleaner.parse(error(429, "Rate limit exceeded"), status: 429) }
        #expect(throws: CleanupError.overloaded) { try OpenRouterCleaner.parse(error(503, "No available provider"), status: 503) }
        #expect(throws: CleanupError.dataPolicy) {
            try OpenRouterCleaner.parse(error(404, "No endpoints found matching your data policy"), status: 404)
        }
        // OpenRouter can put an error in a 200 body.
        #expect(throws: CleanupError.rateLimited) { try OpenRouterCleaner.parse(error(429, "Rate limit exceeded"), status: 200) }
        let filtered = json(["choices": [["message": ["content": ""], "finish_reason": "content_filter"]]])
        #expect(throws: CleanupError.refused) { try OpenRouterCleaner.parse(filtered, status: 200) }
    }

    @Test func readsTodaysFreeAllowanceFromTheKey() throws {
        let data = json(["data": ["label": "notchgate", "is_free_tier": true, "free_model_daily_requests": ["used": 13, "limit": 50, "remaining": 37]]])
        let allowance = try OpenRouterCleaner.parseKeyInfo(data, status: 200)
        #expect(allowance == OpenRouterCleaner.Allowance(used: 13, limit: 50))
        #expect(allowance?.remaining == 37)
        #expect(try OpenRouterCleaner.parseKeyInfo(json(["data": ["label": "x"]]), status: 200) == nil)
        #expect(throws: CleanupError.invalidKey) {
            try OpenRouterCleaner.parseKeyInfo(json(["error": ["code": 401, "message": "User not found."]]), status: 401)
        }
    }

    // MARK: Claude

    @Test func asksHaikuQuicklyWithoutSamplingParameters() throws {
        let body = try ClaudeCleaner.requestBody(transcript: "use us in kuwait here", appName: "Terminal")
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "claude-haiku-5-5")
        #expect((object["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect((object["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(object["temperature"] == nil)
    }

    @Test func readsClaudesTextBlocksAndRefusals() throws {
        let data = json(["stop_reason": "end_turn", "content": [["type": "text", "text": "Use async await here."]]])
        #expect(try ClaudeCleaner.parse(data, status: 200) == "Use async await here.")
        #expect(throws: CleanupError.refused) { try ClaudeCleaner.parse(json(["stop_reason": "refusal", "content": []]), status: 200) }
        let error = { (type: String, message: String) in self.json(["type": "error", "error": ["type": type, "message": message]]) }
        #expect(throws: CleanupError.invalidKey) { try ClaudeCleaner.parse(error("authentication_error", "invalid x-api-key"), status: 401) }
        #expect(throws: CleanupError.noCredit) {
            try ClaudeCleaner.parse(error("invalid_request_error", "Your credit balance is too low"), status: 400)
        }
    }

    // MARK: Safety check on replies

    @Test func keepsRepliesThatAreACleanedCopy() {
        let original = "um so can you like refactor this function so it uh returns early when the user is not logged in"
        #expect(TranscriptCleanup.accept("  So can you refactor this function so it returns early when the user is not logged in?\n", original: original)
            == "So can you refactor this function so it returns early when the user is not logged in?")
        let misheard = "Use us in Kuwait instead of completion handlers and add a unit test for the snooze timer."
        #expect(TranscriptCleanup.accept("Use async await instead of completion handlers and add a unit test for the snooze timer.", original: misheard) != nil)
        #expect(TranscriptCleanup.accept("Fix the bug.", original: "fix the butt") == "Fix the bug.")
    }

    @Test func stripsWrappersModelsAdd() {
        #expect(TranscriptCleanup.accept("<dictation>Hi there.</dictation>", original: "hi there") == "Hi there.")
        #expect(TranscriptCleanup.accept("<think>Fix commas.</think>\nHi there.", original: "hi there") == "Hi there.")
        #expect(TranscriptCleanup.accept("\"Hi there.\"", original: "hi there") == "Hi there.")
    }

    @Test func rejectsAnswersCodeAndRewrites() {
        #expect(TranscriptCleanup.accept("   ", original: "hello there") == nil)
        // Code the dictation only described.
        let code = "```swift\nstruct Response: Codable {\n    let id: Int\n    let title: String\n}\n```"
        #expect(TranscriptCleanup.accept(code, original: "Convert this JSON response into a swift codable model") == nil)
        // An answer instead of the question.
        let essay = String(repeating: "Early returns keep the happy path unindented and easier to read. ", count: 3)
        #expect(TranscriptCleanup.accept(essay, original: "why should I return early from a function") == nil)
        // A different sentence that drops what was said.
        #expect(TranscriptCleanup.accept("Add an async await unit test.", original: "Search the code base for every place we call user defaults directly") == nil)
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
