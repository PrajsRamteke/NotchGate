import Foundation

/// Cactus's needle engine, which runs Whistle and the models built on it (Shruti): their C
/// library (`libneedle3.dylib`, taken out of the Python wheel that downloads with each model)
/// loaded into NotchGate, with the API its `needle.h` declares. The engine holds one speech
/// model per process and isn't thread-safe, so there's one engine, calls take turns, and it
/// loads another model file when a different one is asked for.
final class NeedleEngine: @unchecked Sendable {
    private typealias Load = @convention(c) (UnsafePointer<UInt8>?, UInt64) -> Int32
    private typealias LastError = @convention(c) () -> UnsafePointer<CChar>?
    private typealias Transcribe = @convention(c) (
        UnsafePointer<Float>?, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<CChar>?, Int32
    ) -> Int32

    private struct Library {
        let load: Load
        let transcribe: Transcribe
        let lastError: LastError
    }

    static let shared = NeedleEngine()

    static let library = "libneedle3.dylib"
    private static let libraryInWheel = "needle/libneedle3.dylib"
    /// The engine's JSON reply needs about this much room per second of audio.
    private static let replyBytesPerSecond = 4096

    private let lock = NSLock()
    private var functions: Library?
    private var loaded: URL?
    /// The model file in use, kept for as long as the engine may read it.
    private var weights: Data?

    private init() {}

    /// Loads the engine (from the wheel in `folder`, the first time) and the model file `weights`.
    func prepare(weights: URL, in folder: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if functions == nil { functions = try Self.openLibrary(in: folder) }
        try use(weights)
    }

    /// Text for 16 kHz mono audio of any length, heard by the model in `weights`. `language`
    /// is a code such as "en", or nil to detect it.
    func transcribe(_ audio: [Float], weights: URL, language: String?) throws -> String {
        guard !audio.isEmpty else { return "" }
        lock.lock()
        defer { lock.unlock() }
        guard let functions else { throw VoiceError.notReady }
        try use(weights)

        var reply = [CChar](repeating: 0, count: max(1 << 18, audio.count / 16_000 * Self.replyBytesPerSecond))
        let status = audio.withUnsafeBufferPointer { samples in
            reply.withUnsafeMutableBufferPointer { output in
                Self.withOptionalCString(language) { language in
                    functions.transcribe(samples.baseAddress, Int32(samples.count), language, nil, 0, output.baseAddress, Int32(output.count))
                }
            }
        }
        guard status >= 0 else {
            throw VoiceError.recognitionFailed(Self.message(functions.lastError) ?? "The model couldn't transcribe that")
        }
        return try Self.text(fromReply: reply.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
    }

    /// The transcript in the engine's reply: `{"text":"...","language":"en",...}`.
    static func text(fromReply reply: String) throws -> String {
        struct Reply: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(Reply.self, from: Data(reply.utf8)) else {
            throw VoiceError.recognitionFailed("The model's reply wasn't readable")
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes `url` the engine's speech model. Called with the lock held.
    private func use(_ url: URL) throws {
        guard loaded != url, let functions else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VoiceError.modelLoadFailed(error.localizedDescription)
        }
        let status = data.withUnsafeBytes { bytes in
            functions.load(bytes.bindMemory(to: UInt8.self).baseAddress, UInt64(bytes.count))
        }
        guard status >= 0 else {
            throw VoiceError.modelLoadFailed(Self.message(functions.lastError) ?? "\(url.lastPathComponent) didn't load")
        }
        weights = data
        loaded = url
    }

    private static func openLibrary(in folder: URL) throws -> Library {
        let path = folder.appendingPathComponent(library)
        do {
            if !FileManager.default.fileExists(atPath: path.path) {
                let wheel = try ZipArchive(contentsOf: folder.appendingPathComponent("engine.whl"))
                try wheel.read(libraryInWheel).write(to: path, options: .atomic)
            }
        } catch {
            throw VoiceError.modelLoadFailed("Couldn't unpack the needle engine: \(error.localizedDescription)")
        }
        guard let handle = dlopen(path.path, RTLD_NOW | RTLD_LOCAL) else {
            throw VoiceError.modelLoadFailed(dlerror().map { String(cString: $0) } ?? "The needle engine didn't load")
        }
        guard let load = dlsym(handle, "needle_load"),
              let transcribe = dlsym(handle, "needle_transcribe"),
              let lastError = dlsym(handle, "needle_last_error")
        else { throw VoiceError.modelLoadFailed("The needle engine is missing its speech functions") }
        return Library(
            load: unsafeBitCast(load, to: Load.self),
            transcribe: unsafeBitCast(transcribe, to: Transcribe.self),
            lastError: unsafeBitCast(lastError, to: LastError.self)
        )
    }

    private static func message(_ lastError: LastError) -> String? {
        lastError().map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func withOptionalCString<T>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
        guard let string else { return body(nil) }
        return string.withCString { body($0) }
    }
}
