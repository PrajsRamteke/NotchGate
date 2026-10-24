@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// One dictation's recognizer: audio goes in while the key is held, text comes out on release.
protocol DictationSession: AnyObject, Sendable {
    /// Called on the audio thread with each microphone buffer.
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio: waits for the final text.
    func finish() async throws -> String
    /// Drops the recording.
    func cancel()
}

/// Which Apple recognizer is listening. Every one of them runs on this Mac: no audio
/// is ever sent anywhere.
enum RecognizerKind: Equatable, Sendable {
    /// macOS 26+: Apple's newest speech model, the most accurate available.
    case speechTranscriber
    /// macOS 26+ on Macs that can't run the newest model.
    case dictationTranscriber
    /// macOS 14–15: the older on-device recognizer.
    case legacy

    var needsSpeechPermission: Bool { self == .legacy }
}

/// Picks the best on-device recognizer for a language, makes sure its model is
/// downloaded, and starts sessions with it.
@MainActor
final class SpeechRecognizerProvider {
    private(set) var kind: RecognizerKind?
    private(set) var locale: Locale?
    /// The audio format the macOS 26 analyzer wants (microphone audio is converted to it).
    private var analyzerFormat: AVAudioFormat?

    /// Readies a recognizer for `requested`, downloading Apple's model the first time.
    func prepare(for requested: Locale, progress: @escaping @MainActor (Double) -> Void) async throws -> RecognizerKind {
        kind = nil
        if #available(macOS 26, *) {
            if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
                try await adopt(.speechTranscriber, locale: locale, progress: progress)
                return .speechTranscriber
            }
            if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
                try await adopt(.dictationTranscriber, locale: locale, progress: progress)
                return .dictationTranscriber
            }
        }
        guard let recognizer = SFSpeechRecognizer(locale: requested), recognizer.supportsOnDeviceRecognition else {
            throw VoiceError.languageUnsupported(Self.languageName(requested))
        }
        locale = recognizer.locale
        kind = .legacy
        return .legacy
    }

    /// A new session for one dictation. Audio can be appended straight away: it's held
    /// until the recognizer is up. With `onLiveText`, a fast second listener also reports
    /// what it hears so far, while the accurate one still decides the final text.
    func makeSession(onLiveText: (@Sendable (String) -> Void)? = nil) throws -> DictationSession {
        guard let kind, let locale else { throw VoiceError.notReady }
        switch kind {
        case .speechTranscriber, .dictationTranscriber:
            guard #available(macOS 26, *), let analyzerFormat else { throw VoiceError.notReady }
            return AnalyzerSession(kind: kind, locale: locale, format: analyzerFormat, onLiveText: onLiveText)
        case .legacy:
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw VoiceError.speechRecognitionDenied }
            return try LegacySession(locale: locale, onLiveText: onLiveText)
        }
    }

    @available(macOS 26, *)
    private func adopt(_ kind: RecognizerKind, locale: Locale, progress: @escaping @MainActor (Double) -> Void) async throws {
        let modules = [AnalyzerSession.accurateModule(kind, locale: locale), AnalyzerSession.liveModule(kind, locale: locale)]
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                let watcher = Task { @MainActor in
                    while !Task.isCancelled {
                        progress(request.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer { watcher.cancel() }
                try await request.downloadAndInstall()
            }
        } catch {
            throw VoiceError.modelDownloadFailed(error.localizedDescription)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw VoiceError.languageUnsupported(Self.languageName(locale))
        }
        // Load both listeners now and keep them loaded, so the first dictation starts instantly.
        for module in modules {
            let warmUp = SpeechAnalyzer(modules: [module], options: AnalyzerSession.options)
            try? await warmUp.prepareToAnalyze(in: format)
            await warmUp.cancelAndFinishNow()
        }

        analyzerFormat = format
        self.locale = locale
        self.kind = kind
    }

    nonisolated static func languageName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

// MARK: macOS 26: SpeechAnalyzer

/// Streams microphone audio into `SpeechAnalyzer` while the key is held, so on release
/// only the last moment of speech is left to finish.
///
/// The accurate listener decides what's typed. For live text, a second, fast listener runs
/// in its own analyzer: one analyzer paces every listener to its slowest, which would hold
/// the fast one back to the accurate one's few-second bursts.
@available(macOS 26, *)
final class AnalyzerSession: DictationSession, @unchecked Sendable {
    static let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)

    private let converter: BufferConverter
    private let accurate: Listener
    private let collected: Task<[String], Error>
    private let live: Listener?
    private let streamed: Task<Void, Error>?

    init(kind: RecognizerKind, locale: Locale, format: AVAudioFormat, onLiveText: (@Sendable (String) -> Void)?) {
        converter = BufferConverter(to: format)

        let module = Self.accurateModule(kind, locale: locale)
        switch module {
        case let transcriber as DictationTranscriber:
            collected = Task { try await Self.finalTexts(of: transcriber.results) { String($0.text.characters) } }
        case let transcriber as SpeechTranscriber:
            collected = Task { try await Self.finalTexts(of: transcriber.results) { String($0.text.characters) } }
        default:
            collected = Task { [] }
        }
        accurate = Listener(module)

        guard let onLiveText else {
            live = nil
            streamed = nil
            return
        }
        let liveModule = Self.liveModule(kind, locale: locale)
        switch liveModule {
        case let transcriber as DictationTranscriber:
            streamed = Task { try await Self.stream(transcriber.results, to: onLiveText) { String($0.text.characters) } }
        case let transcriber as SpeechTranscriber:
            streamed = Task { try await Self.stream(transcriber.results, to: onLiveText) { String($0.text.characters) } }
        default:
            streamed = nil
        }
        live = Listener(liveModule)
    }

    /// The model whose text is typed.
    static func accurateModule(_ kind: RecognizerKind, locale: Locale) -> any SpeechModule {
        kind == .dictationTranscriber
            ? DictationTranscriber(locale: locale, preset: .longDictation)
            : SpeechTranscriber(locale: locale, preset: .transcription)
    }

    /// The fast model behind the live text: words about once a second, a little less accurate.
    static func liveModule(_ kind: RecognizerKind, locale: Locale) -> any SpeechModule {
        kind == .dictationTranscriber
            ? DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            : SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        accurate.input.yield(AnalyzerInput(buffer: converted))
        live?.input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws -> String {
        // The live guess has done its job; only the accurate text is typed.
        stopLive()
        accurate.input.finish()
        do {
            try await accurate.started.value
            try await accurate.analyzer.finalizeAndFinishThroughEndOfInput()
            return Self.joined(try await collected.value)
        } catch {
            throw VoiceError.recognitionFailed(error.localizedDescription)
        }
    }

    func cancel() {
        stopLive()
        accurate.input.finish()
        collected.cancel()
        Task { [analyzer = accurate.analyzer] in await analyzer.cancelAndFinishNow() }
    }

    private func stopLive() {
        guard let live else { return }
        live.input.finish()
        streamed?.cancel()
        Task { [analyzer = live.analyzer] in await analyzer.cancelAndFinishNow() }
    }

    /// One analyzer with one model, fed by its own stream.
    private struct Listener {
        let input: AsyncStream<AnalyzerInput>.Continuation
        let analyzer: SpeechAnalyzer
        let started: Task<Void, Error>

        init(_ module: any SpeechModule) {
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            self.input = input
            let analyzer = SpeechAnalyzer(modules: [module], options: AnalyzerSession.options)
            self.analyzer = analyzer
            started = Task { try await analyzer.start(inputSequence: stream) }
        }
    }

    private static func finalTexts<Results: AsyncSequence>(
        of results: Results, text: (Results.Element) -> String
    ) async throws -> [String] where Results.Element: SpeechModuleResult {
        var texts: [String] = []
        for try await result in results where result.isFinal {
            texts.append(text(result))
        }
        return texts
    }

    private static func stream<Results: AsyncSequence>(
        _ results: Results, to onLiveText: @Sendable (String) -> Void, text: (Results.Element) -> String
    ) async throws where Results.Element: SpeechModuleResult {
        var transcript = LiveTranscript()
        for try await result in results {
            transcript.apply(text(result), isFinal: result.isFinal)
            onLiveText(transcript.text)
        }
    }

    static func joined(_ texts: [String]) -> String {
        texts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// What the fast listener has heard so far: the phrases it has settled on, plus its
/// current guess at the words since (which it keeps revising).
struct LiveTranscript: Equatable, Sendable {
    private(set) var settled = ""
    private(set) var guess = ""

    mutating func apply(_ text: String, isFinal: Bool) {
        if isFinal {
            settled += text
            guess = ""
        } else {
            guess = text
        }
    }

    var text: String {
        (settled + " " + guess).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Converts microphone buffers (often 48 kHz stereo float) to the analyzer's format.
/// Used only on the audio thread.
final class BufferConverter: @unchecked Sendable {
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?

    init(to format: AVAudioFormat) {
        self.format = format
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        let source = OneShotBuffer(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let next = source.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}

/// Hands the converter its input buffer once, then reports "no more for now".
private final class OneShotBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

// MARK: macOS 14–15: SFSpeechRecognizer

/// The older recognizer, kept strictly on-device.
final class LegacySession: DictationSession, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let results: AsyncThrowingStream<String, Error>
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale, onLiveText: (@Sendable (String) -> Void)? = nil) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceError.languageUnsupported(SpeechRecognizerProvider.languageName(locale))
        }
        self.recognizer = recognizer
        recognizer.queue = OperationQueue()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = onLiveText != nil
        request.addsPunctuation = true
        request.taskHint = .dictation

        let (results, output) = AsyncThrowingStream<String, Error>.makeStream()
        self.results = results
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal {
                output.yield(result.bestTranscription.formattedString)
                output.finish()
            } else if let result {
                onLiveText?(result.bestTranscription.formattedString)
            } else if let error {
                // 1110: no speech detected; 216 / 301: cancelled. Neither is a failure.
                let code = (error as NSError).code
                if [1110, 216, 301].contains(code) {
                    output.finish()
                } else {
                    output.finish(throwing: VoiceError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() async throws -> String {
        request.endAudio()
        var text = ""
        for try await result in results { text = result }
        return text
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
