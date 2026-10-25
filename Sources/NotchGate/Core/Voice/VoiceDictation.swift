import AppKit
import Observation

/// Notch Voice: hold the shortcut in any app, speak, let go, and the words are typed
/// where the cursor is. The speech model listens on this Mac, so audio never leaves it:
/// Apple's recognizer, or a free open-source model the user downloads (see `SpeechModel`).
/// Its text is typed as is, with no account or API key involved.
@MainActor
@Observable
final class VoiceDictation {
    /// What the pill at the bottom of the screen shows.
    enum Phase: Equatable {
        case idle
        case listening(since: Date)
        case transcribing
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
    /// The downloaded open-source speech models.
    let models: SpeechModelStore

    private(set) var phase: Phase = .idle
    private(set) var model: ModelState = .unloaded
    /// A model getting ready while the current one keeps typing: the first load of a
    /// downloaded model can take minutes.
    private(set) var switchingTo: SpeechModel?
    /// Loudness history for the waveform, oldest first.
    private(set) var levels = Array(repeating: Float(0), count: waveformBars)
    /// The words heard so far, shown in the pill while you talk.
    private(set) var liveText = ""
    private(set) var lastTranscript: String?

    @ObservationIgnored private let recognizer = SpeechRecognizerProvider()
    @ObservationIgnored private var monitor: VoiceKeyMonitor!
    @ObservationIgnored private var overlay: VoiceOverlayController!
    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var session: DictationSession?
    @ObservationIgnored private var restartsLeft = 0
    @ObservationIgnored private var preparedModel: String?
    @ObservationIgnored private var preparedLanguage: String?
    /// Opened System Settings → Accessibility after a dictation couldn't be typed.
    @ObservationIgnored private var showedAccessibilitySettings = false
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var permissionWatch: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(settings: AppSettings, permissions: VoicePermissions = VoicePermissions(), models: SpeechModelStore = SpeechModelStore()) {
        self.settings = settings
        self.permissions = permissions
        self.models = models
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

    // MARK: Speech models

    /// The model that types: the chosen one once it's downloaded, Apple's until then.
    var speechModel: SpeechModel {
        guard let chosen = SpeechModel.withID(settings.voiceModel), models.isDownloaded(chosen), chosen.unsupportedReason == nil else {
            return .apple
        }
        return chosen
    }

    /// The model whose text is typed right now, for the settings.
    var typingModelName: String {
        switch recognizerKind {
        case .bark, .needle: return preparedModel.flatMap(SpeechModel.withID)?.name ?? "The current model"
        case .speechTranscriber, .dictationTranscriber, .legacy, nil: return "Apple's recognizer"
        }
    }

    /// The language `model` listens for: an English accent for Apple's, the model's own choice for others.
    func language(for model: SpeechModel) -> String {
        model.engine == .apple ? settings.voiceLanguage : settings.voiceModelLanguages[model.id] ?? ""
    }

    func setLanguage(_ id: String, for model: SpeechModel) {
        if model.engine == .apple {
            settings.voiceLanguage = id
        } else {
            settings.voiceModelLanguages[model.id] = id.isEmpty ? nil : id
        }
        if settings.voiceEnabled, model == speechModel { prepareModel() }
    }

    /// Types with `model` from now on (it must be downloaded).
    func selectModel(_ model: SpeechModel) {
        guard models.isDownloaded(model), model.unsupportedReason == nil else { return }
        settings.voiceModel = model.id
        guard settings.voiceEnabled, switchingTo != model else { return }
        if preparedModel != model.id || switchingTo != nil { prepareModel() }
    }

    /// Downloads `model`, then switches to it.
    func download(_ model: SpeechModel) {
        models.download(model) { [weak self] succeeded in
            if succeeded { self?.selectModel(model) }
        }
    }

    func cancelDownload(_ model: SpeechModel) {
        models.cancelDownload(model)
    }

    /// Deletes a downloaded model. If it was typing, Apple's takes over.
    func removeModel(_ model: SpeechModel) {
        let wasInUse = speechModel == model || switchingTo == model
        models.remove(model)
        if settings.voiceModel == model.id { settings.voiceModel = SpeechModel.appleID }
        if settings.voiceEnabled, wasInUse { prepareModel() }
    }

    /// Re-reads which models are on disk (the settings call this when they open).
    func refreshModels() {
        models.refresh()
        if settings.voiceEnabled, let preparedModel, preparedModel != speechModel.id, switchingTo == nil { prepareModel() }
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
        let speechModel = self.speechModel
        if preparedModel != speechModel.id || preparedLanguage != language(for: speechModel) || recognizerKind == nil {
            prepareModel()
        }
        watchPermissions()
        if asking { Task { await askForMissingPermissions() } }
    }

    private func deactivate() {
        cancelListening()
        monitor.stop()
        prepareTask?.cancel()
        permissionWatch?.cancel()
        previewTask?.cancel()
        switchingTo = nil
        if case .loading = model { model = .unloaded }
    }

    /// One macOS prompt at a time: the microphone first, then Accessibility.
    private func askForMissingPermissions() async {
        if permissions.microphone == .notAsked { await permissions.requestMicrophone() }
        if !permissions.accessibility { permissions.requestAccessibility() }
    }

    private func prepareModel() {
        prepareTask?.cancel()
        let speechModel = self.speechModel
        let language = language(for: speechModel)
        let folder = models.folder(for: speechModel)
        let progress: @MainActor (Double) -> Void = { [weak self] fraction in
            guard let self, case .loading = self.model else { return }
            self.model = .loading(progress: fraction)
        }
        // A new model gets ready while the current one keeps typing. With nothing ready yet
        // (at launch), Apple's types while a downloaded model is optimized for the first time.
        let hasRecognizer = recognizerKind != nil && preparedModel != speechModel.id
        let needsStandIn = recognizerKind == nil && speechModel.engine == .bark && !BarkTranscriber.isOptimized(in: folder)
        switchingTo = hasRecognizer || needsStandIn ? speechModel : nil
        if !hasRecognizer { model = .loading(progress: nil) }

        prepareTask = Task { [weak self, recognizer] in
            do {
                // Best effort: without a stand-in, dictation just waits for the model.
                if needsStandIn,
                   let kind = try? await recognizer.prepare(.apple, in: folder, language: self?.settings.voiceLanguage ?? "", progress: progress) {
                    guard !Task.isCancelled, let self else { return }
                    self.model = .ready(kind)
                    self.preparedModel = SpeechModel.appleID
                }
                let kind = try await recognizer.prepare(speechModel, in: folder, language: language, progress: progress)
                guard !Task.isCancelled, let self else { return }
                self.model = .ready(kind)
                self.switchingTo = nil
                self.preparedModel = speechModel.id
                self.preparedLanguage = language
                Log.voice.info("Voice ready: \(String(describing: kind), privacy: .public)")
                if kind.needsSpeechPermission, self.permissions.speechRecognition == .notAsked {
                    await self.permissions.requestSpeechRecognition()
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                let failure = error as? VoiceError ?? .modelDownloadFailed(error.localizedDescription)
                self.switchingTo = nil
                self.preparedModel = nil
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
        case .listening, .transcribing: return true
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
            // A fast listener shows the words as you speak.
            let session = try recognizer.makeSession { [weak self] text in
                Task { @MainActor in self?.showLive(text) }
            }
            self.session = session
            levels = Array(repeating: 0, count: Self.waveformBars)
            liveText = ""
            restartsLeft = 2
            try startCapture(into: session)
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
        // Downloaded models may read the whole recording on release: allow for long ones.
        let limit = Self.transcribeTimeout + .seconds(Date().timeIntervalSince(since) / 2)
        finishTask = Task { [weak self] in
            do {
                let text = try await Self.withTimeout(limit) { try await session.finish() }
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
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return show(.nothingHeard) }

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
        case .idle, .listening, .transcribing: nil
        }
        guard let linger else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self else { return }
            self.phase = .idle
            self.overlay.update()
        }
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
                if step % 5 == 4 {
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
