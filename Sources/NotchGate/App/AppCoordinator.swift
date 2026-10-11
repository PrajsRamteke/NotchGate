import Foundation
import NotchGateKit
import Observation

/// Composition root: owns every long-lived service and wires them together.
@MainActor
@Observable
final class AppCoordinator {
    let settings = AppSettings()
    let store = RequestStore()
    let installer = HookInstaller()
    let activity = ActivityTracker()
    let island: IslandViewModel

    private(set) var serverError: String?

    @ObservationIgnored private var server: BridgeServer?
    @ObservationIgnored private var window: NotchWindowController?
    @ObservationIgnored private var hotKeys: HotKeyCenter?

    init() {
        island = IslandViewModel(store: store, settings: settings, activity: activity)
    }

    func start() {
        store.onQueueChange = { [weak self] change in
            self?.island.handle(change)
            self?.syncHotKeys()
        }
        hotKeys = HotKeyCenter { [weak self] action in self?.island.perform(action) }

        startServer()
        installer.upgradeIfNeeded()

        let window = NotchWindowController(viewModel: island)
        window.show()
        self.window = window
    }

    /// Hands every waiting hook back to the terminal so no session hangs.
    func stop() {
        store.releaseAll()
        server?.stop()
        hotKeys?.unregister()
        window?.tearDown()
    }

    /// Injects a sample request so the UI can be previewed without Claude.
    func preview(_ sample: DemoRequests.Sample) {
        store.enqueue(DemoRequests.make(sample), responder: DemoResponder())
    }

    // MARK: Private

    private func startServer() {
        let server = BridgeServer(
            onMessage: { [weak self] message, responder in self?.handle(message, responder: responder) },
            onDisconnect: { [weak self] id in self?.store.cancel(id) }
        )
        do {
            try server.start()
            self.server = server
            serverError = nil
        } catch {
            serverError = String(describing: error)
            Log.bridge.error("Bridge failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ message: BridgeRequest, responder: DecisionResponder) {
        activity.ingest(message)
        let router = RequestRouter(options: settings.routerOptions)
        let route = router.route(message)
        if RequestRouter.clearsSessionFirst(message.event) {
            store.clearSession(message.payload["session_id"]?.stringValue ?? "")
        }
        switch route {
        case .present(let request):
            store.enqueue(request, responder: responder)
        case .notice(let notice):
            store.post(notice)
            if message.expectsReply { responder.send(.passthrough) }
        case .clearSession(let sessionID):
            store.clearSession(sessionID)
        case .toolCompleted(let sessionID, let toolName, let input):
            store.dismissCompletedTool(sessionID: sessionID, toolName: toolName, input: input)
        case .autoRespond(let decision):
            responder.send(decision)
        case .ignore:
            if message.expectsReply { responder.send(.passthrough) }
        }
    }

    /// Global shortcuts are only claimed while something is waiting, so
    /// NotchGate never shadows other apps' shortcuts when idle.
    private func syncHotKeys() {
        if store.hasPending { hotKeys?.register() } else { hotKeys?.unregister() }
    }
}
