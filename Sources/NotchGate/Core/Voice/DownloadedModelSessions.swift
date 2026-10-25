@preconcurrency import AVFoundation
import Foundation

/// The microphone audio of one dictation at 16 kHz mono, for the downloaded models: they
/// read stretches of audio rather than a live stream. Appended on the audio thread.
final class RecordedAudio: @unchecked Sendable {
    private let converter = BufferConverter(to: BarkTranscriber.audioFormat, downmix: true)
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer), let channel = converted.floatChannelData?[0] else { return }
        let new = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
        lock.withLock { samples.append(contentsOf: new) }
    }

    /// The audio so far, without copying it. Keep `body` quick: the microphone waits meanwhile.
    func read<T>(_ body: ([Float]) -> T) -> T {
        lock.withLock { body(samples) }
    }

    static func joined(_ texts: [String]) -> String {
        texts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: Underdog Bark

/// Dictation with Underdog Bark. While the key is held the audio is cut into pieces at
/// pauses (see `BarkSegmenter`) and each finished piece is read straight away, so on release
/// only the last piece is left. With live text, the piece in progress is also read about
/// once a second for the pill.
final class BarkSession: DictationSession, @unchecked Sendable {
    private static let pace: Duration = .milliseconds(800)

    private let transcriber: BarkTranscriber
    private let audio = RecordedAudio()
    private let onLiveText: (@Sendable (String) -> Void)?
    private var worker: Task<Void, Never>?
    // The worker's, then finish()'s once the worker has stopped.
    private var settledEnd = 0
    private var settled: [String] = []
    private var failure: Error?

    init(transcriber: BarkTranscriber, onLiveText: (@Sendable (String) -> Void)?) {
        self.transcriber = transcriber
        self.onLiveText = onLiveText
        worker = Task.detached(priority: .userInitiated) { [weak self] in await self?.listen() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        audio.append(buffer)
    }

    func finish() async throws -> String {
        worker?.cancel()
        await worker?.value
        return try await Task.detached(priority: .userInitiated) { [self] in
            if let failure { throw VoiceError.recognitionFailed(failure.localizedDescription) }
            do {
                try settle(isFinal: true)
                let rest = audio.read { Array($0[settledEnd...]) }
                if !rest.isEmpty { settled.append(try transcriber.transcribe(rest[...])) }
            } catch let error as VoiceError {
                throw error
            } catch {
                throw VoiceError.recognitionFailed(error.localizedDescription)
            }
            return RecordedAudio.joined(settled)
        }.value
    }

    func cancel() {
        worker?.cancel()
    }

    private func listen() async {
        let sampleRate = BarkTranscriber.sampleRate
        var heard = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pace)
            guard !Task.isCancelled else { return }
            do {
                try settle(isFinal: false)
            } catch {
                failure = error
                return
            }
            guard let onLiveText else { continue }
            // The words so far: the finished pieces, plus a first reading of the one in progress.
            let (tail, total) = audio.read { (Array($0[settledEnd...]), $0.count) }
            guard total - heard >= sampleRate / 4, tail.count >= sampleRate / 2 else { continue }
            heard = total
            guard let guess = try? transcriber.transcribe(tail[...]), !Task.isCancelled else { continue }
            onLiveText(RecordedAudio.joined(settled + [guess]))
        }
    }

    /// Reads every piece that's finished: the audio up to the last cut at a pause.
    private func settle(isFinal: Bool) throws {
        while true {
            // Copied while the lock is held, so the microphone never copies the whole recording.
            let piece: [Float]? = audio.read { samples in
                guard let cut = BarkSegmenter.cut(samples, from: settledEnd, isFinal: isFinal) else { return nil }
                defer { settledEnd = cut }
                return Array(samples[settledEnd..<cut])
            }
            guard let piece else { return }
            settled.append(try transcriber.transcribe(piece[...]))
        }
    }
}

// MARK: Whistle and Shruti

/// Dictation with a needle-engine model (Whistle, Shruti): the audio is kept while the key
/// is held and read in one go on release (the engine reads 30 seconds per pass and windows
/// longer audio itself).
final class NeedleSession: DictationSession, @unchecked Sendable {
    private let engine: NeedleEngine
    private let weights: URL
    private let language: String?
    private let audio = RecordedAudio()

    init(engine: NeedleEngine, weights: URL, language: String?) {
        self.engine = engine
        self.weights = weights
        self.language = language
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        audio.append(buffer)
    }

    func finish() async throws -> String {
        let samples = audio.read { $0 }
        return try await Task.detached(priority: .userInitiated) { [engine, weights, language] in
            try engine.transcribe(samples, weights: weights, language: language)
        }.value
    }

    func cancel() {}
}
