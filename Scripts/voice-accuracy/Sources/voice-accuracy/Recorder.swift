import AVFoundation

/// Records the default microphone into a CAF file between `start` and `stop`.
final class Recorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func start(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw ToolError("No microphone input is available.") }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        self.file = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and returns the clip's length in seconds.
    @discardableResult
    func stop() -> Double {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        defer { file = nil }
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
