@preconcurrency import AVFoundation

/// Records the default microphone while the shortcut is held. Every buffer goes to the
/// recognizer; a loudness reading per slice goes to the waveform.
///
/// The tap runs on an audio thread. The handlers are fixed at init and never change,
/// and the engine is only touched from the main actor, so sharing is safe.
final class AudioCapture: @unchecked Sendable {
    /// Loudness slices per tap buffer: enough for a smooth waveform.
    static let sliceFrames = 512

    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onLevels: @Sendable ([Float]) -> Void
    private let onInterrupted: @Sendable () -> Void
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?

    init(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevels: @escaping @Sendable ([Float]) -> Void,
        onInterrupted: @escaping @Sendable () -> Void
    ) {
        self.onBuffer = onBuffer
        self.onLevels = onLevels
        self.onInterrupted = onInterrupted
    }

    @MainActor
    func start() throws {
        // A fresh engine each time picks up the current input device.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.noMicrophone }

        installTap(on: input, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw VoiceError.microphoneFailed(error.localizedDescription)
        }
        self.engine = engine
        // The input device changed or vanished (headphones unplugged): the engine stops.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [onInterrupted] _ in onInterrupted() }
    }

    @MainActor
    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Taps `node` for the recognizer and the waveform (tests tap an offline engine).
    @MainActor
    func installTap(on node: AVAudioNode, format: AVAudioFormat?) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(onBuffer: onBuffer, onLevels: onLevels))
    }

    /// The tap runs on an audio thread. Built outside the main actor on purpose: a closure
    /// written inside a main-actor method is isolated to it, and Swift stops the app
    /// when the audio thread calls it.
    private static func tapBlock(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevels: @escaping @Sendable ([Float]) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            onBuffer(buffer)
            onLevels(levels(in: buffer))
        }
    }

    /// Loudness of each slice of the buffer, 0 (silence) to 1 (loud speech).
    static func levels(in buffer: AVAudioPCMBuffer) -> [Float] {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return [] }
        let count = Int(buffer.frameLength)
        return stride(from: 0, to: count, by: sliceFrames).map { start in
            let end = min(start + sliceFrames, count)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            return normalized(rms: (sum / Float(end - start)).squareRoot())
        }
    }

    /// Maps RMS onto 0…1 over the range speech actually spans (−55 dB to −12 dB).
    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 55) / 43))
    }
}
