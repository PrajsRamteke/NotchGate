@preconcurrency import AVFoundation
import Foundation

/// The microphone audio of one dictation at 16 kHz mono, for the downloaded models: they
/// read stretches of audio rather than a live stream. Appended on the audio thread.
final class RecordedAudio: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let converter = BufferConverter(to: RecordedAudio.format, downmix: true)
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
