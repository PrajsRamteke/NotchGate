import AppKit

/// Watches the keyboard everywhere for the hold-to-talk shortcut and reports when to
/// start, finish or drop a dictation (see `HoldDetector` for the rules).
///
/// A global monitor only sees other apps' events, and only once NotchGate has
/// Accessibility permission; a local one covers NotchGate's own windows. Neither
/// swallows the keys, which suits modifier keys: on their own they type nothing.
@MainActor
final class VoiceKeyMonitor {
    enum Event { case begin, end, cancel }

    var shortcut: VoiceShortcut {
        get { detector.shortcut }
        set {
            detector.shortcut = newValue
            reset()
        }
    }

    /// Ignore the shortcut for a while, e.g. while a new one is being recorded.
    var isPaused = false {
        didSet { if isPaused { reset() } }
    }

    private let onEvent: (Event) -> Void
    private var detector: HoldDetector
    private var monitors: [Any] = []
    private var armTask: Task<Void, Never>?

    init(shortcut: VoiceShortcut, onEvent: @escaping (Event) -> Void) {
        detector = HoldDetector(shortcut: shortcut)
        self.onEvent = onEvent
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    /// Restarts the monitors. A global monitor added before Accessibility was granted
    /// stays deaf, so this runs once permission arrives.
    func restart() {
        stop()
        start()
    }

    private func reset() {
        armTask?.cancel()
        armTask = nil
        if detector.phase == .active { onEvent(.cancel) }
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        guard !isPaused else { return }
        let action: HoldDetector.Action?
        switch event.type {
        case .flagsChanged:
            action = detector.modifiersChanged(to: ModifierKey.held(in: event.modifierFlags.rawValue))
        case .keyDown:
            action = detector.keyPressed()
        default:
            action = detector.mousePressed()
        }
        if let action { perform(action) }
    }

    private func perform(_ action: HoldDetector.Action) {
        switch action {
        case .startArmTimer:
            armTask?.cancel()
            armTask = Task { [weak self] in
                try? await Task.sleep(for: HoldDetector.armDelay)
                guard !Task.isCancelled, let self, let next = self.detector.armTimerFired() else { return }
                self.perform(next)
            }
        case .cancelArmTimer:
            armTask?.cancel()
            armTask = nil
        case .begin: onEvent(.begin)
        case .end: onEvent(.end)
        case .cancel: onEvent(.cancel)
        }
    }
}
