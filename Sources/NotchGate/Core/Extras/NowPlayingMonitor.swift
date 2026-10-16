import AppKit
import CoreImage
import NotchGateKit
import Observation

/// The Now Playing extra: what's playing on the Mac (Music, Spotify, Podcasts,
/// a YouTube tab…) and the remote that controls it.
///
/// Since macOS 15.4 MediaRemote only answers Apple-signed processes, so the app
/// can't ask it directly. Instead it starts `/usr/bin/perl` with our small
/// `NotchGateMedia` library loaded into it: the library streams one JSON line per
/// change and takes commands on stdin, and quits when the app closes that pipe.
@MainActor
@Observable
final class NowPlayingMonitor {
    private(set) var track: NowPlayingTrack?
    private(set) var artwork: NSImage?
    /// A small, heavily blurred copy of the artwork for the card's background wash.
    private(set) var backdrop: NSImage?
    /// A color picked from the artwork for the card's glow, progress bar and equalizer.
    private(set) var accent: NSColor?
    /// The player's app icon, for the source badge.
    private(set) var appIcon: NSImage?
    /// Why nothing can be shown, for the menu bar and the card.
    private(set) var setupError: String?
    /// Showing a sample track (snapshots); no helper runs.
    private(set) var isPreviewing = false

    let settings: AppSettings

    @ObservationIgnored private var helper: Process?
    @ObservationIgnored private var commands: FileHandle?
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var iconBundleID: String?
    /// Recent unexpected exits; a helper that keeps dying isn't restarted forever.
    @ObservationIgnored private var crashes: [Date] = []
    @ObservationIgnored private var restart: Task<Void, Never>?

    static let libraryName = "libNotchGateMedia.dylib"
    static let restartDelay: Duration = .seconds(2)
    static let maxCrashesPerMinute = 3

    /// Loads the library into perl and calls its entry point, which never returns.
    static let hostScript = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $run = DynaLoader::dl_find_symbol($lib, "notchgate_media_run") or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", $run);
        run();
        """

    /// The library ships next to the app executable (in `swift build` output and in `Contents/MacOS`).
    static var libraryURL: URL? {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(libraryName),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isEnabled: Bool { settings.nowPlaying || isPreviewing }

    func start() {
        if settings.nowPlaying { launch() }
    }

    func stop() {
        restart?.cancel()
        let running = helper
        helper = nil
        // Closing stdin is the helper's cue to exit; terminate in case it's stuck.
        try? commands?.close()
        commands = nil
        running?.terminate()
    }

    func setEnabled(_ enabled: Bool) {
        settings.nowPlaying = enabled
        if enabled {
            crashes = []
            setupError = nil
            launch()
        } else {
            stop()
            clear()
            setupError = nil
        }
    }

    /// Shows `sample` without running the helper (snapshots).
    func showPreview(_ sample: NowPlayingTrack?, artwork: NSImage? = nil) {
        isPreviewing = true
        track = sample
        setArtwork(artwork, key: artwork == nil ? nil : "preview")
        loadIcon(for: sample?.appBundleID)
    }

    // MARK: Intents

    func togglePlayPause() {
        let now = Date()
        update { track in
            track.elapsed = track.position(at: now)
            track.sampledAt = now
            track.isPlaying.toggle()
        }
        send(.togglePlayPause)
    }

    func nextTrack() {
        send(.nextTrack)
    }

    func previousTrack() {
        send(.previousTrack)
    }

    func seek(to seconds: TimeInterval) {
        guard let duration = track?.duration else { return }
        let target = min(max(0, seconds), duration)
        update { track in
            track.elapsed = target
            track.sampledAt = Date()
        }
        send(.seek(to: target))
    }

    /// Jumps back or ahead (±15 s), for podcasts and videos.
    func skip(by seconds: TimeInterval) {
        guard let position = track?.position(at: Date()) else { return }
        seek(to: position + seconds)
    }

    func toggleShuffle() {
        guard let track else { return }
        let mode = track.isShuffling ? 1 : 3
        update { $0.shuffleMode = mode }
        send(track.supports(.changeShuffleMode) ? .setShuffleMode(mode) : .advanceShuffleMode)
    }

    /// Off → all → one → off, like Music. Players that only step through their
    /// own modes report back where they landed.
    func cycleRepeat() {
        guard let track else { return }
        let mode: Int
        switch track.repeating {
        case .off: mode = 3
        case .all: mode = 2
        case .one: mode = 1
        }
        update { $0.repeatMode = mode }
        send(track.supports(.changeRepeatMode) ? .setRepeatMode(mode) : .advanceRepeatMode)
    }

    /// Brings the player (or the browser playing it) to the front.
    func openPlayer() {
        guard let id = track?.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Helper process

    private func launch() {
        guard helper == nil, !isPreviewing else { return }
        guard let library = Self.libraryURL else {
            setupError = "The media helper (\(Self.libraryName)) is missing next to the app. Reinstall NotchGate."
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.hostScript, library.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = MessageReader { [weak self] message, artwork in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(message, artwork: artwork) }
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperExited(process, status: status) }
            }
        }

        do {
            try process.run()
        } catch {
            setupError = "Couldn't start the media helper: \(error.localizedDescription)"
            Log.app.error("Now Playing helper failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }
        // A write after the helper died must fail, not kill the app with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        helper = process
        commands = input.fileHandleForWriting
        setupError = nil
    }

    private func helperExited(_ process: Process, status: Int32) {
        // `stop()` already let go of it: an exit on purpose.
        guard process === helper else { return }
        helper = nil
        commands = nil
        clear()
        guard settings.nowPlaying else { return }

        Log.app.error("Now Playing helper exited with status \(status, privacy: .public)")
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard crashes.count <= Self.maxCrashesPerMinute else {
            setupError = "The media helper keeps stopping (exit \(status)). Turn Now playing off and on to retry."
            return
        }
        restart = Task { [weak self] in
            try? await Task.sleep(for: Self.restartDelay)
            guard let self, !Task.isCancelled, settings.nowPlaying else { return }
            launch()
        }
    }

    private func send(_ command: NowPlayingCommand) {
        guard let commands else { return }
        try? commands.write(contentsOf: Data((command.line + "\n").utf8))
    }

    // MARK: State

    private func receive(_ message: NowPlayingMessage, artwork data: Data?) {
        guard helper != nil else { return }
        let next = NowPlayingTrack(message).map { $0.keepingPlayhead(of: track, at: Date()).keepingModes(of: track) }
        if next != track { track = next }
        loadIcon(for: next?.appBundleID)
        guard next != nil, let key = message.artworkKey else {
            if artworkKey != nil { setArtwork(nil, key: nil) }
            return
        }
        if key != artworkKey, let data, let image = NSImage(data: data) {
            setArtwork(image, key: key)
        }
    }

    /// Optimistic local change, so buttons respond before the player reports back.
    private func update(_ change: (inout NowPlayingTrack) -> Void) {
        guard var track else { return }
        change(&track)
        self.track = track
    }

    private func setArtwork(_ image: NSImage?, key: String?) {
        artworkKey = key
        artwork = image
        accent = image.flatMap(ArtworkPalette.accent(of:))
        backdrop = image.flatMap(ArtworkPalette.backdrop(of:))
    }

    private func loadIcon(for bundleID: String?) {
        guard bundleID != iconBundleID else { return }
        iconBundleID = bundleID
        appIcon = bundleID
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func clear() {
        track = nil
        setArtwork(nil, key: nil)
        iconBundleID = nil
        appIcon = nil
    }
}

/// Splits the helper's output into lines and decodes them off the main thread.
/// `readabilityHandler` calls come one at a time, so the buffer needs no lock.
private final class MessageReader: @unchecked Sendable {
    private var buffer = Data()
    private let decoder = JSONDecoder()
    private let deliver: @Sendable (NowPlayingMessage, Data?) -> Void

    init(deliver: @escaping @Sendable (NowPlayingMessage, Data?) -> Void) {
        self.deliver = deliver
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            defer { buffer.removeSubrange(buffer.startIndex...newline) }
            guard let message = try? decoder.decode(NowPlayingMessage.self, from: line) else { continue }
            deliver(message, message.artwork.flatMap { Data(base64Encoded: $0) })
        }
    }
}

/// Picks one lively color from artwork, the way Music tints its player.
enum ArtworkPalette {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The artwork shrunk and blurred into a soft wash of its colors. Done once
    /// per track, so the card never runs a live blur.
    static func backdrop(of image: NSImage) -> NSImage? {
        let side: CGFloat = 64
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let source = CIImage(cgImage: cgImage)
        let scale = side / max(source.extent.width, source.extent.height, 1)
        let blurred = source
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 7)
            .cropped(to: CGRect(x: 0, y: 0, width: source.extent.width * scale, height: source.extent.height * scale))
        guard let output = context.createCGImage(blurred, from: blurred.extent) else { return nil }
        return NSImage(cgImage: output, size: blurred.extent.size)
    }

    static func accent(of image: NSImage) -> NSColor? {
        let side = 24
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        // Weight each pixel by how colorful it is, so a grey background doesn't win.
        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let saturation = color.saturationComponent, brightness = color.brightnessComponent
                let weight = 0.05 + saturation * saturation * (brightness > 0.15 ? 1 : 0.1)
                red += color.redComponent * weight
                green += color.greenComponent * weight
                blue += color.blueComponent * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        let average = NSColor(deviceRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        // Bright enough to glow on black; muted artwork stays muted rather than turning neon.
        let saturation = average.saturationComponent < 0.12 ? average.saturationComponent : max(0.45, min(0.85, average.saturationComponent * 1.35))
        return NSColor(
            deviceHue: average.hueComponent,
            saturation: saturation,
            brightness: max(0.78, min(0.95, average.brightnessComponent * 1.6)),
            alpha: 1
        )
    }
}
