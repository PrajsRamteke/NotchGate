import Foundation

/// Runs a command-line tool off the main thread with a hard timeout.
enum CommandRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { status == 0 }
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        stdin: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 5
    ) async throws(PromptDeliveryError) -> Output {
        let result: Result<Output, PromptDeliveryError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, arguments, stdin, environment, timeout))
            }
        }
        return try result.get()
    }

    private static func runBlocking(
        _ executable: String, _ arguments: [String], _ stdin: String?,
        _ environment: [String: String], _ timeout: TimeInterval
    ) -> Result<Output, PromptDeliveryError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failure(.commandFailed("couldn't start \(URL(fileURLWithPath: executable).lastPathComponent)"))
        }
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inPipe.fileHandleForWriting.close()

        // Drain output concurrently so a chatty tool can't fill the pipe and stall.
        let outData = DataBox(), errData = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData.set(outPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData.set(errPipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return .failure(.timedOut(URL(fileURLWithPath: executable).lastPathComponent))
        }
        group.wait()
        return .success(Output(
            status: process.terminationStatus,
            stdout: String(decoding: outData.value, as: UTF8.self),
            stderr: String(decoding: errData.value, as: UTF8.self)
        ))
    }

    /// Finds an executable in `searchPath` (the session's own PATH) and the
    /// usual Homebrew locations, since GUI apps don't inherit a shell PATH.
    static func locate(_ tool: String, searchPath: String?, extra: [String] = []) -> String? {
        let directories = (searchPath ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + extra
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(tool).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Thread-safe holder for bytes read on a background queue.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data { lock.withLock { data } }
    func set(_ newValue: Data) { lock.withLock { data = newValue } }
}
