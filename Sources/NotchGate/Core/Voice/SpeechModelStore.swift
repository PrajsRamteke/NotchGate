import CryptoKit
import Foundation
import Observation

/// The open-source speech models on this Mac. Downloads them from Hugging Face into
/// ~/Library/Application Support/NotchGate/Speech Models, checks every file against its
/// published size and SHA-256 before using it, and removes them again.
@MainActor
@Observable
final class SpeechModelStore {
    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)
    }

    struct DownloadError: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchGate/Speech Models", isDirectory: true)
    }

    /// Allows two minutes without a byte before giving up on a request (the CDN can stall).
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration)
    }()

    let folder: URL
    private(set) var states: [String: State] = [:]
    @ObservationIgnored private var downloads: [String: Task<Void, Never>] = [:]

    init(folder: URL = SpeechModelStore.defaultFolder) {
        self.folder = folder
        refresh()
    }

    func state(of model: SpeechModel) -> State {
        model.isBuiltIn ? .downloaded : states[model.id] ?? .notDownloaded
    }

    func isDownloaded(_ model: SpeechModel) -> Bool {
        state(of: model) == .downloaded
    }

    func folder(for model: SpeechModel) -> URL {
        folder.appendingPathComponent(model.id, isDirectory: true)
    }

    /// Re-reads what's on disk. Cheap: it checks sizes; checksums were checked on download.
    func refresh() {
        for model in SpeechModel.catalog where !model.isBuiltIn {
            switch states[model.id] {
            case .downloading: continue
            case .failed where !Self.hasAllFiles(model, in: folder(for: model)): continue
            default: states[model.id] = Self.hasAllFiles(model, in: folder(for: model)) ? .downloaded : .notDownloaded
            }
        }
    }

    /// Downloads every file of `model`, then calls `completion` with whether it worked.
    func download(_ model: SpeechModel, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !model.isBuiltIn, downloads[model.id] == nil else { return }
        states[model.id] = .downloading(progress: 0)
        let staging = folder.appendingPathComponent(model.id + ".partial", isDirectory: true)
        let destination = folder(for: model)
        downloads[model.id] = Task { [weak self] in
            var succeeded = false
            do {
                try await Self.fetch(model, into: staging) { fraction in
                    Task { @MainActor in self?.showProgress(fraction, of: model) }
                }
                try Self.install(staging, at: destination)
                self?.states[model.id] = .downloaded
                succeeded = true
                Log.voice.info("Downloaded \(model.name, privacy: .public)")
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: staging)
                self?.states[model.id] = .notDownloaded
            } catch {
                // Files that finished stay in the staging folder, so trying again picks up from there.
                let reason = (error as? URLError).map(Self.describe) ?? error.localizedDescription
                self?.states[model.id] = .failed(reason)
                Log.voice.error("\(model.name, privacy: .public) didn't download: \(reason, privacy: .public)")
            }
            self?.downloads[model.id] = nil
            completion(succeeded)
        }
    }

    func cancelDownload(_ model: SpeechModel) {
        downloads[model.id]?.cancel()
    }

    /// Deletes the model's files (and any half-finished download).
    func remove(_ model: SpeechModel) {
        guard !model.isBuiltIn else { return }
        cancelDownload(model)
        try? FileManager.default.removeItem(at: folder(for: model))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(model.id + ".partial", isDirectory: true))
        states[model.id] = .notDownloaded
    }

    /// Puts a model in a given state, for snapshots.
    func showPreview(_ state: State, for model: SpeechModel) {
        states[model.id] = state
    }

    private func showProgress(_ fraction: Double, of model: SpeechModel) {
        guard case .downloading = states[model.id] else { return }
        states[model.id] = .downloading(progress: min(1, fraction))
    }

    // MARK: Files

    /// Every file is there at its published size. A Core ML package also counts once it has
    /// been compiled, since the compiled copy replaces it (see `BarkTranscriber`).
    nonisolated static func hasAllFiles(_ model: SpeechModel, in folder: URL) -> Bool {
        let manager = FileManager.default
        return model.files.allSatisfy { file in
            if let package = file.path.split(separator: "/").first, package.hasSuffix(".mlpackage") {
                let compiled = package.dropLast(".mlpackage".count) + ".mlmodelc"
                if manager.fileExists(atPath: folder.appendingPathComponent(String(compiled)).path) { return true }
            }
            let attributes = try? manager.attributesOfItem(atPath: folder.appendingPathComponent(file.path).path)
            return (attributes?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    private nonisolated static func fetch(
        _ model: SpeechModel, into staging: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        let available = (try? staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        // Room for the files, plus what Core ML writes while compiling a package.
        if let available, available < model.downloadSize * 2 {
            throw DownloadError(reason: "Not enough free disk space: \(model.name) needs about \(ByteCountFormatter.string(fromByteCount: model.downloadSize * 2, countStyle: .file)).")
        }

        let total = Double(model.downloadSize)
        var finished: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(file.path)
            // Already here from an interrupted download.
            if manager.fileExists(atPath: target.path), try await sha256(of: target) == file.sha256 {
                finished += file.size
                progress(Double(finished) / total)
                continue
            }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = finished
            try await download(file, to: target) { received in progress(Double(before + received) / total) }
            let size = (try? manager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value
            guard size == file.size, try await sha256(of: target) == file.sha256 else {
                try? manager.removeItem(at: target)
                throw DownloadError(reason: "\(file.path) didn't match its published checksum. Try again.")
            }
            finished += file.size
            progress(Double(finished) / total)
        }
    }

    private nonisolated static func install(_ staging: URL, at destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: staging, to: destination)
    }

    /// One file, reporting how many of its bytes are here. A dropped or stalled connection
    /// is retried a few times, carrying on from where it stopped.
    private nonisolated static func download(
        _ file: SpeechModel.File, to target: URL, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let attempts = 4
        var resumeData: Data?
        for attempt in 1...attempts {
            do {
                return try await download(file, resumingFrom: resumeData, to: target, progress: progress)
            } catch let error as URLError where attempt < attempts && isTransient(error) {
                resumeData = error.downloadTaskResumeData
                Log.voice.info("\(file.path, privacy: .public) interrupted (\(error.code.rawValue)), resuming: \(resumeData != nil)")
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }
    }

    private nonisolated static func download(
        _ file: SpeechModel.File, resumingFrom resumeData: Data?, to target: URL, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let url = file.url
        let handle = DownloadHandle()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion: @Sendable (URL?, URLResponse?, Error?) -> Void = { location, response, error in
                    if let error {
                        let cancelled = (error as? URLError)?.code == .cancelled
                        return continuation.resume(throwing: cancelled ? CancellationError() : error)
                    }
                    guard let location, let status = (response as? HTTPURLResponse)?.statusCode, status == 200 || status == 206 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        return continuation.resume(throwing: DownloadError(reason: "Hugging Face answered \(status) for \(url.lastPathComponent)."))
                    }
                    do {
                        try? FileManager.default.removeItem(at: target)
                        try FileManager.default.moveItem(at: location, to: target)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                let task = resumeData.map { session.downloadTask(withResumeData: $0, completionHandler: completion) }
                    ?? session.downloadTask(with: url, completionHandler: completion)
                handle.start(task, size: file.size, progress: progress)
            }
        } onCancel: {
            handle.cancel()
        }
    }

    /// SHA-256 of a file, read in pieces (the largest file is 189 MB).
    nonisolated static func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hasher = SHA256()
            while let chunk = try file.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private nonisolated static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
         .dnsLookupFailed, .resourceUnavailable].contains(error.code)
    }

    private nonisolated static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return "No internet connection."
        case .timedOut: return "Hugging Face took too long to answer."
        default: return error.localizedDescription
        }
    }
}

/// A download task that can be cancelled before or after it starts, and that reports the
/// file's bytes here so far four times a second while it runs (counting a resumed start).
private final class DownloadHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var isCancelled = false

    func start(_ task: URLSessionDownloadTask, size: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        let cancelled = lock.withLock {
            self.task = task
            return isCancelled
        }
        task.resume()
        if cancelled { return task.cancel() }
        Task.detached {
            while task.state == .running {
                // What's left to come, taken from the whole: right whether or not a resumed
                // task counts the bytes it started with.
                let expected = task.countOfBytesExpectedToReceive
                progress(expected > 0 ? max(0, size - (expected - task.countOfBytesReceived)) : task.countOfBytesReceived)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func cancel() {
        let task = lock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }
}
