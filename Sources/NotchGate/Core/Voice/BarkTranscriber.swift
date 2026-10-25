import Accelerate
@preconcurrency import AVFoundation
import CoreML
import CryptoKit
import Foundation

/// Underdog Bark 3.0 on this Mac, with no Python: the encoder runs as Core ML on the Neural
/// Engine, and the audio frontend and the greedy TDT decoder run here on the CPU. A port of
/// the model's reference implementation, `coreml/ane/bark_coreml.py`.
///
/// Only the 15-second window is loaded: the Neural Engine optimizes each window the first
/// time it's loaded on a Mac, and that takes minutes; the 8-second one would only be a few
/// tens of milliseconds faster.
final class BarkTranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    /// 16 kHz mono float: what the model hears (microphone audio is converted to it).
    static let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
    static let windowSeconds = 15
    /// Silence added in front of every piece: the setting the model was scored with.
    static let leadingSilence = sampleRate / 4
    /// The longest piece one window reads; longer audio is cut at pauses (see `BarkSegmenter`).
    static let maxPiece = windowSeconds * sampleRate - leadingSilence

    /// Left in the model's folder once the Neural Engine has optimized it. Core ML keeps that
    /// work per build of the app and per macOS, so after an update it's done again.
    private static var optimizedMarker: String {
        let built = (try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let build = "\(Int(built?.timeIntervalSince1970 ?? 0))|\(ProcessInfo.processInfo.operatingSystemVersionString)"
        let digest = SHA256.hash(data: Data(build.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(markerPrefix)\(digest)"
    }

    /// Each app (NotchGate, NotchGate Dev) keeps its own marker beside the shared model.
    private static var markerPrefix: String {
        ".optimized-\(Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)-"
    }

    private let encoder: MLModel
    private let frontend: BarkFrontend
    private let decoder: BarkDecoder
    /// One piece at a time: a cancelled dictation's last piece may still be running.
    private let lock = NSLock()

    private init(encoder: MLModel, frontend: BarkFrontend, decoder: BarkDecoder) {
        self.encoder = encoder
        self.frontend = frontend
        self.decoder = decoder
    }

    /// Whether loading will be quick, rather than the few minutes of a first load (for this
    /// build of NotchGate on this macOS).
    static func isOptimized(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(optimizedMarker).path)
    }

    /// Compiles the downloaded package once, then loads it for the Neural Engine. The first
    /// load on a Mac takes a few minutes while macOS optimizes the model; later ones take a moment.
    static func load(from folder: URL) async throws -> BarkTranscriber {
        guard #available(macOS 15, *) else { throw VoiceError.modelUnsupported("Underdog Bark needs macOS 15 or later.") }
        do {
            let compiled = folder.appendingPathComponent("BarkEncoder.mlmodelc")
            if !FileManager.default.fileExists(atPath: compiled.path) {
                let package = folder.appendingPathComponent("BarkEncoder.mlpackage")
                let temporary = try await MLModel.compileModel(at: package)
                try FileManager.default.moveItem(at: temporary, to: compiled)
                // The compiled copy holds the same 182 MB of weights: keep one (`SpeechModelStore` knows).
                try? FileManager.default.removeItem(at: package)
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            configuration.functionName = "w\(windowSeconds)"
            let encoder = try await MLModel.load(contentsOf: compiled, configuration: configuration)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let vocabulary = try decoder.decode(BarkVocabulary.self, from: Data(contentsOf: folder.appendingPathComponent("vocab.json")))
            let weights = try NumpyArchive(contentsOf: folder.appendingPathComponent("decoder.npz"))
            let transcriber = try BarkTranscriber(
                encoder: encoder,
                frontend: BarkFrontend(melFilters: weights.floats("mel_filters")),
                decoder: BarkDecoder(weights: weights, vocabulary: vocabulary)
            )
            // The first prediction is slower; take it now rather than on the first dictation.
            _ = try transcriber.transcribe([Float](repeating: 0, count: sampleRate)[...])
            markOptimized(in: folder)
            return transcriber
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Leaves this build's marker in place of the app's earlier one.
    private static func markOptimized(in folder: URL) {
        let marker = optimizedMarker
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(markerPrefix) && name != marker {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        FileManager.default.createFile(atPath: folder.appendingPathComponent(marker).path, contents: nil)
    }

    /// One piece of 16 kHz mono audio, at most `maxPiece` samples long.
    func transcribe(_ piece: ArraySlice<Float>) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        var audio = [Float](repeating: 0, count: Self.leadingSilence)
        audio.append(contentsOf: piece.prefix(Self.maxPiece))
        let features = frontend.features(audio)
        let window = Self.windowSeconds * 100 + 1
        let output = try encoder.prediction(from: Self.encoderInput(features, window: window))
        guard let encoded = output.featureValue(for: "encoded")?.multiArrayValue else {
            throw VoiceError.recognitionFailed("The speech model gave no output.")
        }
        let frames = min(Self.encodedLength(features.valid), encoded.shape[1].intValue)
        let rows = Self.floats(encoded, rows: frames, width: decoder.hidden)
        guard rows.allSatisfy(\.isFinite) else { throw VoiceError.recognitionFailed("The speech model's output wasn't finite.") }
        return decoder.vocabulary.text(decoder.decode(rows, frames: frames))
    }

    /// Frames left after the encoder's three stride-2 convolutions (kernel 3, padding 1).
    static func encodedLength(_ frames: Int) -> Int {
        var length = frames
        for _ in 0..<3 { length = (length - 1) / 2 + 1 }
        return length
    }

    /// FP16 features `[1, window, 128]`, zero past the audio, and the mask `[1, window]` of frames that hold audio.
    private static func encoderInput(_ features: BarkFrontend.Features, window: Int) throws -> MLFeatureProvider {
        let mels = BarkFrontend.mels
        let values = try MLMultiArray(shape: [1, NSNumber(value: window), NSNumber(value: mels)], dataType: .float16)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: window)], dataType: .int32)

        let rows = min(features.frames, window)
        var halves = [UInt16](repeating: 0, count: window * mels)
        features.values.withUnsafeBufferPointer { floats in
            halves.withUnsafeMutableBufferPointer { output in
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: floats.baseAddress!), height: 1,
                                           width: vImagePixelCount(rows * mels), rowBytes: rows * mels * 4)
                var destination = vImage_Buffer(data: output.baseAddress!, height: 1,
                                                width: vImagePixelCount(rows * mels), rowBytes: rows * mels * 2)
                vImageConvert_PlanarFtoPlanar16F(&source, &destination, 0)
            }
        }
        values.withUnsafeMutableBytes { raw, strides in
            let destination = raw.bindMemory(to: UInt16.self)
            for row in 0..<window {
                for column in 0..<mels {
                    destination[row * strides[1] + column * strides[2]] = halves[row * mels + column]
                }
            }
        }
        mask.withUnsafeMutableBytes { raw, strides in
            let destination = raw.bindMemory(to: Int32.self)
            for frame in 0..<window { destination[frame * strides[1]] = frame < features.valid ? 1 : 0 }
        }
        return try MLDictionaryFeatureProvider(dictionary: ["features": values, "mask": mask])
    }

    /// The first `rows` encoder frames as Float, row-major `[rows, width]`, whatever the output's layout.
    private static func floats(_ array: MLMultiArray, rows: Int, width: Int) -> [Float] {
        var output = [Float](repeating: 0, count: rows * width)
        array.withUnsafeBytes { raw in
            let rowStride = array.strides[1].intValue
            let columnStride = array.strides[2].intValue
            switch array.dataType {
            case .float16:
                let halves = raw.bindMemory(to: UInt16.self)
                var row = [UInt16](repeating: 0, count: width)
                for index in 0..<rows {
                    for column in 0..<width { row[column] = halves[index * rowStride + column * columnStride] }
                    let floats = NumpyArchive.halfToFloat(row.withUnsafeBytes { Data($0) }, count: width)
                    output.replaceSubrange((index * width)..<((index + 1) * width), with: floats)
                }
            default:
                let floats = raw.bindMemory(to: Float.self)
                for index in 0..<rows {
                    for column in 0..<width { output[index * width + column] = floats[index * rowStride + column * columnStride] }
                }
            }
        }
        return output
    }
}

/// The model's tokenizer and decoding settings (`vocab.json`).
struct BarkVocabulary: Decodable, Sendable {
    let pieces: [String]
    let specialIds: [Int]
    let blankId: Int
    let vocabSize: Int
    let durations: [Int]
    let maxSymbolsPerStep: Int

    /// The words for token ids: SentencePiece pieces, with ▁ marking a space.
    func text(_ tokens: [Int]) -> String {
        let special = Set(specialIds)
        return tokens
            .filter { !special.contains($0) && $0 < pieces.count }
            .map { pieces[$0] }
            .joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Frontend

/// Log-mel features, as transformers' `ParakeetFeatureExtractor` makes them: pre-emphasis,
/// a centred STFT, slaney mel filters, log, and per-utterance normalization.
struct BarkFrontend: Sendable {
    static let hop = 160
    static let fftSize = 512
    static let windowLength = 400
    static let bins = fftSize / 2 + 1
    static let mels = 128

    struct Features {
        /// Row-major `[frames, mels]`.
        let values: [Float]
        let frames: Int
        /// Frames that hold audio; the rest are zero.
        let valid: Int
    }

    /// `[bins, mels]`: the mel filters, transposed.
    private let melFilters: [Float]
    /// `[fftSize, 2 × bins]`: the Hann window times cos, then times sin, so one matrix
    /// product gives each frame's real and imaginary spectrum.
    private let basis: [Float]

    init(melFilters filters: [Float]) throws {
        let bins = Self.bins, mels = Self.mels, size = Self.fftSize
        guard filters.count == mels * bins else { throw VoiceError.modelLoadFailed("Unexpected mel filters") }
        var transposed = [Float](repeating: 0, count: bins * mels)
        vDSP_mtrans(filters, 1, &transposed, 1, vDSP_Length(bins), vDSP_Length(mels))
        melFilters = transposed

        // np.hanning(400): symmetric, centred in the 512-sample frame.
        let offset = (size - Self.windowLength) / 2
        var basis = [Float](repeating: 0, count: size * 2 * bins)
        for sample in 0..<Self.windowLength {
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(sample) / Double(Self.windowLength - 1))
            let n = sample + offset
            for bin in 0..<bins {
                let angle = 2 * Double.pi * Double(n * bin % size) / Double(size)
                basis[n * 2 * bins + bin] = Float(window * cos(angle))
                basis[n * 2 * bins + bins + bin] = Float(-window * sin(angle))
            }
        }
        self.basis = basis
    }

    func features(_ audio: [Float]) -> Features {
        let hop = Self.hop, size = Self.fftSize, bins = Self.bins, mels = Self.mels
        let length = audio.count
        guard length > 0 else { return Features(values: [], frames: 0, valid: 0) }

        // Pre-emphasis, then half a frame of zeros on each side.
        var padded = [Float](repeating: 0, count: length + size)
        padded[size / 2] = audio[0]
        for index in 1..<length { padded[size / 2 + index] = audio[index] - 0.97 * audio[index - 1] }

        let frames = 1 + length / hop
        var framed = [Float](repeating: 0, count: frames * size)
        for frame in 0..<frames {
            framed.replaceSubrange((frame * size)..<((frame + 1) * size), with: padded[(frame * hop)..<(frame * hop + size)])
        }

        var spectrum = [Float](repeating: 0, count: frames * 2 * bins)
        vDSP_mmul(framed, 1, basis, 1, &spectrum, 1, vDSP_Length(frames), vDSP_Length(2 * bins), vDSP_Length(size))
        var power = [Float](repeating: 0, count: frames * bins)
        for frame in 0..<frames {
            for bin in 0..<bins {
                let real = spectrum[frame * 2 * bins + bin], imaginary = spectrum[frame * 2 * bins + bins + bin]
                power[frame * bins + bin] = real * real + imaginary * imaginary
            }
        }

        var values = [Float](repeating: 0, count: frames * mels)
        vDSP_mmul(power, 1, melFilters, 1, &values, 1, vDSP_Length(frames), vDSP_Length(mels), vDSP_Length(bins))
        var floor: Float = 1.0 / Float(1 << 24)
        var count = Int32(values.count)
        values.withUnsafeMutableBufferPointer { logs in
            vDSP_vsadd(logs.baseAddress!, 1, &floor, logs.baseAddress!, 1, vDSP_Length(logs.count))
            vvlogf(logs.baseAddress!, logs.baseAddress!, &count)
        }

        // Each mel band to zero mean and unit variance over the frames that hold audio.
        let valid = length / hop
        for mel in 0..<mels {
            var sum = 0.0
            for frame in 0..<valid { sum += Double(values[frame * mels + mel]) }
            let mean = valid > 0 ? sum / Double(valid) : 0
            var squares = 0.0
            for frame in 0..<valid {
                let deviation = Double(values[frame * mels + mel]) - mean
                squares += deviation * deviation
            }
            let spread = (squares / Double(max(1, valid - 1))).squareRoot() + 1e-5
            for frame in 0..<frames {
                values[frame * mels + mel] = frame < valid ? Float((Double(values[frame * mels + mel]) - mean) / spread) : 0
            }
        }
        return Features(values: values, frames: frames, valid: valid)
    }
}

// MARK: Decoder

/// Greedy TDT decoding, as transformers' `ParakeetForTDT.generate` does it for one clip: a
/// 2-layer LSTM predicts from the words so far, and a joint head reads it with each encoder
/// frame to pick the next token and how many frames to skip.
struct BarkDecoder: Sendable {
    private struct Layer {
        let inputWeights: [Float]
        let hiddenWeights: [Float]
        let bias: [Float]
    }

    let hidden: Int
    let vocabulary: BarkVocabulary
    /// int8, one row per token, times `embeddingScales` (dequantized a row at a time).
    private let embedding: [Int8]
    private let embeddingScales: [Float]
    private let layers: [Layer]
    private let projectionWeights: [Float]
    private let projectionBias: [Float]
    private let headWeights: [Float]
    private let headBias: [Float]

    init(weights: NumpyArchive, vocabulary: BarkVocabulary) throws {
        self.vocabulary = vocabulary
        let embedding = try weights.array("decoder.embedding.weight.q")
        guard embedding.dtype == "|i1", embedding.shape.count == 2 else { throw VoiceError.modelLoadFailed("Unexpected embedding") }
        hidden = embedding.shape[1]
        self.embedding = embedding.bytes.withUnsafeBytes { Array($0.bindMemory(to: Int8.self).prefix(embedding.count)) }
        embeddingScales = try weights.floats("decoder.embedding.weight.s")
        layers = try (0..<2).map { index in
            let inputBias = try weights.dequantized("decoder.lstm.bias_ih_l\(index)")
            let hiddenBias = try weights.dequantized("decoder.lstm.bias_hh_l\(index)")
            return Layer(
                inputWeights: try weights.dequantized("decoder.lstm.weight_ih_l\(index)"),
                hiddenWeights: try weights.dequantized("decoder.lstm.weight_hh_l\(index)"),
                bias: zip(inputBias, hiddenBias).map(+)
            )
        }
        projectionWeights = try weights.dequantized("decoder.decoder_projector.weight")
        projectionBias = try weights.dequantized("decoder.decoder_projector.bias")
        headWeights = try weights.dequantized("joint.head.weight")
        headBias = try weights.dequantized("joint.head.bias")
        guard headBias.count == vocabulary.vocabSize + vocabulary.durations.count,
              layers.allSatisfy({ $0.bias.count == 4 * hidden }) else {
            throw VoiceError.modelLoadFailed("The decoder doesn't match its vocabulary")
        }
    }

    /// Token ids for `frames` encoder frames, row-major `[frames, hidden]`.
    func decode(_ encoded: [Float], frames: Int) -> [Int] {
        let vocabularySize = vocabulary.vocabSize, blank = vocabulary.blankId
        var states = [[Float]](repeating: [Float](repeating: 0, count: hidden), count: 4)  // h, c per layer
        var prediction = step(blank, &states)
        var joint = [Float](repeating: 0, count: hidden)
        var logits = [Float](repeating: 0, count: headBias.count)
        var zero: Float = 0

        var frame = 0, symbols = 0
        var tokens: [Int] = []
        while frame < frames {
            encoded.withUnsafeBufferPointer { rows in
                joint.withUnsafeMutableBufferPointer { sum in
                    // relu(encoder frame + prediction)
                    vDSP_vadd(rows.baseAddress! + frame * hidden, 1, prediction, 1, sum.baseAddress!, 1, vDSP_Length(hidden))
                    vDSP_vthr(sum.baseAddress!, 1, &zero, sum.baseAddress!, 1, vDSP_Length(hidden))
                }
            }
            multiply(headWeights, joint, adding: headBias, into: &logits)

            let token = Self.argmax(logits, 0..<vocabularySize)
            var skip = vocabulary.durations[Self.argmax(logits, vocabularySize..<logits.count) - vocabularySize]
            if token == blank {
                frame += max(skip, 1)
                symbols = 0
            } else {
                tokens.append(token)
                prediction = step(token, &states)
                symbols += 1
                if skip == 0, symbols >= vocabulary.maxSymbolsPerStep { skip = 1 }
                if skip > 0 { symbols = 0 }
                frame += skip
            }
        }
        return tokens
    }

    /// Feeds one token through the LSTM; returns the projected prediction.
    private func step(_ token: Int, _ states: inout [[Float]]) -> [Float] {
        var input = [Float](repeating: 0, count: hidden)
        var scale = embeddingScales[token]
        embedding.withUnsafeBufferPointer { rows in
            input.withUnsafeMutableBufferPointer { row in
                vDSP_vflt8(rows.baseAddress! + token * hidden, 1, row.baseAddress!, 1, vDSP_Length(hidden))
                vDSP_vsmul(row.baseAddress!, 1, &scale, row.baseAddress!, 1, vDSP_Length(hidden))
            }
        }

        var gates = [Float](repeating: 0, count: 4 * hidden)
        var recurrent = [Float](repeating: 0, count: 4 * hidden)
        var sum = [Float](repeating: 0, count: 4 * hidden)
        for (index, layer) in layers.enumerated() {
            multiply(layer.inputWeights, input, adding: layer.bias, into: &gates)
            multiply(layer.hiddenWeights, states[2 * index], adding: nil, into: &recurrent)
            vDSP_vadd(gates, 1, recurrent, 1, &sum, 1, vDSP_Length(gates.count))
            swap(&gates, &sum)
            // PyTorch's gate order: input, forget, cell, output.
            for unit in 0..<hidden {
                let inputGate = Self.sigmoid(gates[unit])
                let forgetGate = Self.sigmoid(gates[hidden + unit])
                let cell = tanh(gates[2 * hidden + unit])
                let outputGate = Self.sigmoid(gates[3 * hidden + unit])
                let memory = forgetGate * states[2 * index + 1][unit] + inputGate * cell
                states[2 * index + 1][unit] = memory
                states[2 * index][unit] = outputGate * tanh(memory)
            }
            input = states[2 * index]
        }
        var output = [Float](repeating: 0, count: hidden)
        multiply(projectionWeights, input, adding: projectionBias, into: &output)
        return output
    }

    /// `output = matrix × vector (+ bias)`, the matrix row-major with `output.count` rows.
    private func multiply(_ matrix: [Float], _ vector: [Float], adding bias: [Float]?, into output: inout [Float]) {
        output.withUnsafeMutableBufferPointer { result in
            vDSP_mmul(matrix, 1, vector, 1, result.baseAddress!, 1, vDSP_Length(result.count), 1, vDSP_Length(vector.count))
            if let bias { vDSP_vadd(result.baseAddress!, 1, bias, 1, result.baseAddress!, 1, vDSP_Length(result.count)) }
        }
    }

    /// The first index of the largest value, like NumPy's argmax.
    private static func argmax(_ values: [Float], _ range: Range<Int>) -> Int {
        var best = range.lowerBound
        for index in range where values[index] > values[best] { best = index }
        return best
    }

    private static func sigmoid(_ value: Float) -> Float {
        1 / (1 + exp(-value))
    }
}

// MARK: Segments

/// Where Underdog Bark's pieces end: audio longer than one window is cut at a pause, in the
/// middle of the quietest 200 ms between 5 s and the window's end, so no word is split.
enum BarkSegmenter {
    /// 10 ms of audio.
    static let frame = BarkTranscriber.sampleRate / 100
    static let minPiece = 5 * BarkTranscriber.sampleRate
    /// Frames on each side of a frame that its smoothed loudness reads (20 in all).
    private static let smoothing = 10

    /// The end of the piece that starts at `start`, or nil when the rest fits in one piece.
    /// While audio is still arriving (`isFinal` false), a cut waits until the audio reaches
    /// 100 ms past the window, which the smoothing reads.
    static func cut(_ audio: [Float], from start: Int, maxPiece: Int = BarkTranscriber.maxPiece, isFinal: Bool = true) -> Int? {
        guard audio.count - start > maxPiece + (isFinal ? 0 : smoothing * frame) else { return nil }
        let frames = audio.count / frame
        let low = (start + minPiece) / frame
        let high = (start + maxPiece) / frame

        // Mean square of each 10 ms frame the search reads; frames past the audio are silent.
        let first = low - smoothing
        let energies: [Double] = audio.withUnsafeBufferPointer { samples in
            (first..<(high + smoothing)).map { index in
                guard index >= 0, index < frames else { return 0 }
                var meanSquare: Float = 0
                vDSP_measqv(samples.baseAddress! + index * frame, 1, &meanSquare, vDSP_Length(frame))
                return Double(meanSquare)
            }
        }
        // np.convolve(energy, ones(20) / 20, "same"): frame i averages frames i-10 … i+9.
        var quietest = low
        var lowest = Double.infinity
        for index in low..<high {
            let window = energies[(index - smoothing - first)..<(index + smoothing - first)]
            let loudness = window.reduce(0, +) / Double(2 * smoothing)
            if loudness < lowest {
                lowest = loudness
                quietest = index
            }
        }
        return quietest * frame + frame / 2
    }
}
