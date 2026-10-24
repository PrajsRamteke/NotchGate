import AppKit
import Observation

/// Notch Voice: hold the shortcut in any app, speak, let go, and the words are typed
/// where the cursor is. Apple's on-device recognizer does the listening, so audio never
/// leaves the Mac; optionally a model tidies the text first (OpenRouter's free models or
/// Claude Haiku), with the user's own API key.
@MainActor
@Observable
final class VoiceDictation {
    /// What the pill at the bottom of the screen shows.
    enum Phase: Equatable {
        case idle
        case listening(since: Date)
        case transcribing
        case cleaningUp(CleanupService)
        case inserted(words: Int)
        case copied(TextInserter.CopyReason)
        case nothingHeard
        case failed(VoiceError)
    }

    /// Whether holding the shortcut will work, for the settings.
    enum Readiness: Equatable {
        case off
        case needsPermissions
        case preparing(progress: Double?)
        case ready
        case failed(VoiceError)
    }

    /// The on-device speech model for the chosen language.
    enum ModelState: Equatable {
        case unloaded
        case loading(progress: Double?)
        case ready(RecognizerKind)
        case failed(VoiceError)
    }

    static let waveformBars = 28
    /// A press shorter than this was a tap, not dictation.
    static let minimumHold: TimeInterval = 0.3
    static let maximumHold: Duration = .seconds(180)
    static let transcribeTimeout: Duration = .seconds(20)

    let settings: AppSettings
    let permissions: VoicePermissions

    private(set) var phase: Phase = .idle
    private(set) var model: ModelState = .unloaded
    /// Loudness history for the waveform, oldest first.
    private(set) var levels = Array(repeating: Float(0), count: waveformBars)
    /// With AI clean-up off: the words heard so far, shown in the pill while you talk.
    private(set) var liveText = ""
    private(set) var lastTranscript: String?
    /// Why the last clean-up didn't happen, if it didn't.
    private(set) var cleanupError: String?
    /// The clean-up services with a key in the keychain.
    private(set) var savedKeys: Set<CleanupService> = []
    /// OpenRouter's free requests today, when known.
    private(set) var freeAllowance: OpenRouterCleaner.Allowance?

    @ObservationIgnored private let recognizer = SpeechRecognizerProvider()
    @ObservationIgnored private var monitor: VoiceKeyMonitor!
    @ObservationIgnored private var overlay: VoiceOverlayController!
    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var session: DictationSession?
    @ObservationIgnored private var restartsLeft = 0
    @ObservationIgnored private var targetApp: String?
    @ObservationIgnored private var preparedLanguage: String?
    @ObservationIgnored private var cachedKeys: [CleanupService: String] = [:]
    /// Opened System Settings → Accessibility after a dictation couldn't be typed.
    @ObservationIgnored private var showedAccessibilitySettings = false
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var permissionWatch: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(settings: AppSettings, permissions: VoicePermissions = VoicePermissions()) {
        self.settings = settings
        self.permissions = permissions
        monitor = VoiceKeyMonitor(shortcut: settings.voiceShortcut) { [weak self] event in self?.handle(event) }
        overlay = VoiceOverlayController(dictation: self)
    }

    var recognizerKind: RecognizerKind? {
        if case .ready(let kind) = model { return kind }
        return nil
    }

    var readiness: Readiness {
        guard settings.voiceEnabled else { return .off }
        if Self.isUnbundled { return .failed(.unbundled) }
        if case .failed(let error) = model { return .failed(error) }
        if !missingPermissions.isEmpty { return .needsPermissions }
        switch model {
        case .ready: return .ready
        case .loading(let progress): return .preparing(progress: progress)
        case .unloaded, .failed: return .preparing(progress: nil)
        }
    }

    /// The permissions still to grant, in the order to ask for them.
    var missingPermissions: [VoicePermissions.Pane] {
        var missing: [VoicePermissions.Pane] = []
        if permissions.microphone != .granted { missing.append(.microphone) }
        if !permissions.accessibility { missing.append(.accessibility) }
        if recognizerKind?.needsSpeechPermission == true, permissions.speechRecognition != .granted {
            missing.append(.speechRecognition)
        }
        return missing
    }

    // MARK: Lifecycle

    func start() {
        savedKeys = Set(CleanupService.allCases.filter { APIKeyStore.exists(for: $0) })
        if settings.voiceEnabled { activate(asking: false) }
    }

    func stop() {
        deactivate()
    }

    /// The settings switch. Turning it on asks for whatever permission is missing.
    func setEnabled(_ enabled: Bool) {
        settings.voiceEnabled = enabled
        if enabled { activate(asking: true) } else { deactivate() }
    }

    func setShortcut(_ shortcut: VoiceShortcut) {
        settings.voiceShortcut = shortcut
        monitor.shortcut = shortcut
    }

    func setLanguage(_ id: String) {
        settings.voiceLanguage = id
        if settings.voiceEnabled { prepareModel() }
    }

    /// While the settings record a new shortcut, holding keys mustn't start dictation.
    var isRecordingShortcut: Bool {
        get { monitor.isPaused }
        set { monitor.isPaused = newValue }
    }

    /// Re-reads permissions (the settings call this when they open).
    func refreshPermissions() {
        let hadAccessibility = permissions.accessibility
        permissions.refresh()
        // A global monitor added before Accessibility was granted never hears anything.
        if settings.voiceEnabled, permissions.accessibility, !hadAccessibility { monitor.restart() }
    }

    func request(_ pane: VoicePermissions.Pane) {
        switch pane {
        case .microphone: Task { await permissions.requestMicrophone() }
        case .accessibility: permissions.requestAccessibility()
        case .speechRecognition: Task { await permissions.requestSpeechRecognition() }
        }
    }

    /// After a failed download, try again.
    func retryModel() {
        prepareModel()
    }

    private func activate(asking: Bool) {
        guard !Self.isUnbundled else { return }
        overlay.prepare()
        refreshPermissions()
        monitor.start()
        if preparedLanguage != settings.voiceLanguage || recognizerKind == nil { prepareModel() }
        watchPermissions()
        if asking { Task { await askForMissingPermissions() } }
    }

    private func deactivate() {
        cancelListening()
        monitor.stop()
        prepareTask?.cancel()
        permissionWatch?.cancel()
        previewTask?.cancel()
        if case .loading = model { model = .unloaded }
    }

    /// One macOS prompt at a time: the microphone first, then Accessibility.
    private func askForMissingPermissions() async {
        if permissions.microphone == .notAsked { await permissions.requestMicrophone() }
        if !permissions.accessibility { permissions.requestAccessibility() }
    }

    private func prepareModel() {
        prepareTask?.cancel()
        let language = settings.voiceLanguage
        model = .loading(progress: nil)
        prepareTask = Task { [weak self, recognizer] in
            do {
                let kind = try await recognizer.prepare(for: VoiceLanguage.locale(for: language)) { fraction in
                    guard let self, case .loading = self.model else { return }
                    self.model = .loading(progress: fraction)
                }
                guard !Task.isCancelled, let self else { return }
                self.model = .ready(kind)
                self.preparedLanguage = language
                Log.voice.info("Voice ready: \(String(describing: kind), privacy: .public)")
                if kind.needsSpeechPermission, self.permissions.speechRecognition == .notAsked {
                    await self.permissions.requestSpeechRecognition()
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                let failure = error as? VoiceError ?? .modelDownloadFailed(error.localizedDescription)
                self.model = .failed(failure)
                Log.voice.error("Voice model failed: \(failure.detail, privacy: .public)")
            }
        }
    }

    /// Notices permissions granted (or revoked) in System Settings while NotchGate runs.
    private func watchPermissions() {
        permissionWatch?.cancel()
        permissionWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.settings.voiceEnabled else { return }
                self.refreshPermissions()
                let wait: Duration = self.missingPermissions.isEmpty ? .seconds(5) : .seconds(1)
                try? await Task.sleep(for: wait)
            }
        }
    }

    // MARK: Dictation

    private func handle(_ event: VoiceKeyMonitor.Event) {
        switch event {
        case .begin: beginListening()
        case .end: endListening()
        case .cancel: cancelListening()
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .listening, .transcribing, .cleaningUp: return true
        default: return false
        }
    }

    private func beginListening() {
        // A real hold always wins over the ▶ preview.
        if let previewTask {
            previewTask.cancel()
            self.previewTask = nil
            phase = .idle
        }
        guard settings.voiceEnabled, !isBusy else { return }
        permissions.refresh()
        if permissions.microphone != .granted { return show(.failed(.microphoneDenied)) }
        switch model {
        case .ready: break
        case .failed(let error): return show(.failed(error))
        case .loading, .unloaded: return show(.failed(.notReady))
        }

        do {
            // With AI clean-up off, a fast listener shows the words as you speak.
            var onLiveText: (@Sendable (String) -> Void)?
            if !settings.voiceCleanupEnabled {
                onLiveText = { [weak self] text in
                    Task { @MainActor in self?.showLive(text) }
                }
            }
            let session = try recognizer.makeSession(onLiveText: onLiveText)
            self.session = session
            levels = Array(repeating: 0, count: Self.waveformBars)
            liveText = ""
            restartsLeft = 2
            try startCapture(into: session)
            targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
            show(.listening(since: Date()))
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: Self.maximumHold)
                guard !Task.isCancelled else { return }
                self?.endListening()
            }
        } catch {
            session?.cancel()
            session = nil
            show(.failed(error as? VoiceError ?? .microphoneFailed(error.localizedDescription)))
        }
    }

    private func startCapture(into session: DictationSession) throws {
        let capture = AudioCapture(
            onBuffer: { buffer in session.append(buffer) },
            onLevels: { [weak self] levels in
                Task { @MainActor in self?.push(levels) }
            },
            onInterrupted: { [weak self] in
                Task { @MainActor in self?.captureInterrupted() }
            }
        )
        try capture.start()
        self.capture = capture
    }

    private func endListening() {
        guard case .listening(let since) = phase, let session else { return }
        limitTask?.cancel()
        capture?.stop()
        capture = nil
        self.session = nil
        if Date().timeIntervalSince(since) < Self.minimumHold {
            session.cancel()
            return show(.idle)
        }

        show(.transcribing)
        finishTask = Task { [weak self] in
            do {
                let text = try await Self.withTimeout(Self.transcribeTimeout) { try await session.finish() }
                await self?.deliver(text)
            } catch {
                let failure = error as? VoiceError ?? .recognitionFailed(error.localizedDescription)
                Log.voice.error("Transcription failed: \(failure.detail, privacy: .public)")
                self?.show(.failed(failure))
                // The model may have been removed from disk: get it again for next time.
                if case .recognitionFailed = failure { self?.prepareModel() }
            }
        }
    }

    private func cancelListening() {
        guard case .listening = phase else { return }
        limitTask?.cancel()
        capture?.stop()
        capture = nil
        session?.cancel()
        session = nil
        show(.idle)
    }

    /// The input device changed mid-dictation (Bluetooth headsets do this as they switch
    /// to their microphone): carry on with the new device, or keep what was said so far.
    private func captureInterrupted() {
        guard case .listening = phase, let session else { return }
        capture?.stop()
        capture = nil
        if restartsLeft > 0 {
            restartsLeft -= 1
            do {
                try startCapture(into: session)
                return
            } catch {
                Log.voice.error("Microphone restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        endListening()
    }

    private func deliver(_ transcript: String) async {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return show(.nothingHeard) }

        let service = settings.voiceCleanup
        if settings.voiceCleanupEnabled, let key = await apiKey(for: service) {
            show(.cleaningUp(service))
            do {
                text = try await TranscriptCleanup.clean(text, appName: targetApp, service: service, key: key)
                cleanupError = nil
                if service == .openRouter, let allowance = freeAllowance {
                    freeAllowance = .init(used: allowance.used + 1, limit: allowance.limit)
                }
            } catch {
                cleanupError = (error as? CleanupError)?.message(for: service) ?? error.localizedDescription
                Log.voice.error("Clean-up skipped: \(self.cleanupError ?? "", privacy: .public)")
            }
        }

        lastTranscript = text
        switch await TextInserter.insert(text) {
        case .pasted:
            show(.inserted(words: text.split(whereSeparator: \.isWhitespace).count))
        case .copied(let reason):
            show(.copied(reason))
            guard reason == .accessibilityOff else { break }
            // The words couldn't be typed: take the user to the switch once, so the next one is.
            permissions.refresh()
            if !showedAccessibilitySettings {
                showedAccessibilitySettings = true
                VoicePermissions.openSettings(.accessibility)
            }
        }
    }

    private func showLive(_ text: String) {
        guard case .listening = phase else { return }
        liveText = text
    }

    private func push(_ newLevels: [Float]) {
        guard case .listening = phase, !newLevels.isEmpty else { return }
        levels = Array((levels + newLevels).suffix(Self.waveformBars))
    }

    private func show(_ next: Phase) {
        dismissTask?.cancel()
        phase = next
        overlay.update()
        let linger: Duration? = switch next {
        case .inserted: .milliseconds(1100)
        case .copied: .milliseconds(2800)
        case .nothingHeard: .milliseconds(1600)
        case .failed: .milliseconds(3400)
        case .idle, .listening, .transcribing, .cleaningUp: nil
        }
        guard let linger else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self else { return }
            self.phase = .idle
            self.overlay.update()
        }
    }

    // MARK: Clean-up

    /// The AI clean-up switch. Off, the words show live in the pill while you talk.
    func setCleanupEnabled(_ enabled: Bool) {
        settings.voiceCleanupEnabled = enabled
        cleanupError = nil
        if enabled, settings.voiceCleanup == .openRouter { refreshFreeAllowance() }
    }

    func setCleanup(_ service: CleanupService) {
        settings.voiceCleanup = service
        cleanupError = nil
        if service == .openRouter { refreshFreeAllowance() }
    }

    func hasKey(for service: CleanupService) -> Bool {
        savedKeys.contains(service)
    }

    /// Checks the key, then keeps it in the keychain. Returns a problem to show, or nil
    /// when the key was saved.
    func saveAPIKey(_ input: String, for service: CleanupService) async -> String? {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix(service.keyPrefix) else {
            return "That isn't an \(service.providerName) API key (they start with \(service.keyPrefix))."
        }
        do {
            switch service {
            // Free to check: reading the key's info spends no request.
            case .openRouter: freeAllowance = try await OpenRouterCleaner(apiKey: key).checkKey()
            case .claude: _ = try await ClaudeCleaner(apiKey: key).clean("testing one two three", appName: nil)
            }
        } catch let error as CleanupError where error == .invalidKey || error == .noCredit {
            return error.message(for: service)
        } catch {
            // Offline or busy: the key may still be fine, so keep it.
        }
        guard APIKeyStore.save(key, for: service) else { return "Couldn't save the key to the keychain." }
        cachedKeys[service] = key
        savedKeys.insert(service)
        cleanupError = nil
        return nil
    }

    func removeAPIKey(for service: CleanupService) {
        APIKeyStore.delete(for: service)
        cachedKeys[service] = nil
        savedKeys.remove(service)
        if service == .openRouter { freeAllowance = nil }
        cleanupError = nil
    }

    /// Reads how many free OpenRouter requests are left today (spends none).
    func refreshFreeAllowance() {
        guard hasKey(for: .openRouter) else { return }
        Task { [weak self] in
            guard let self, let key = await self.apiKey(for: .openRouter) else { return }
            if let allowance = try? await OpenRouterCleaner(apiKey: key).checkKey() { self.freeAllowance = allowance }
        }
    }

    /// Read off the main thread: after an update macOS may ask for the login password
    /// before handing the key over, and the pill must keep animating meanwhile.
    private func apiKey(for service: CleanupService) async -> String? {
        if let key = cachedKeys[service] { return key }
        let key = await Task.detached { APIKeyStore.read(for: service) }.value
        cachedKeys[service] = key
        if key == nil { savedKeys.remove(service) } else { savedKeys.insert(service) }
        return key
    }

    // MARK: Previews

    /// The ▶ button: plays a pretend dictation so you can see the pill and where it sits.
    func preview() {
        guard !isBusy else { return }
        overlay.prepare()
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            self.levels = Array(repeating: 0, count: Self.waveformBars)
            self.liveText = ""
            self.show(.listening(since: Date()))
            let words = "Can you refactor this function so it returns early".split(separator: " ")
            for step in 0..<48 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, case .listening = self.phase else { return }
                let speech = 0.35 + 0.3 * sin(Double(step) / 2.3) + Double.random(in: -0.15...0.25)
                self.levels = Array((self.levels + [Float(max(0.05, min(1, speech)))]).suffix(Self.waveformBars))
                if !self.settings.voiceCleanupEnabled, step % 5 == 4 {
                    self.liveText = words.prefix(step / 5 + 1).joined(separator: " ")
                }
            }
            self.show(.transcribing)
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, self.phase == .transcribing else { return }
            self.show(.inserted(words: 12))
        }
    }

    /// Puts the pill in a given state, for snapshots.
    func showPreview(_ phase: Phase, levels: [Float]? = nil, liveText: String = "") {
        if let levels { self.levels = levels }
        self.liveText = liveText
        self.phase = phase
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    // MARK: Helpers

    /// Run via `swift run` there's no app bundle, and macOS refuses the microphone to it.
    static var isUnbundled: Bool { Bundle.main.bundleIdentifier == nil }

    private static func withTimeout<T: Sendable>(
        _ limit: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw VoiceError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw VoiceError.timedOut }
            return result
        }
    }
}
