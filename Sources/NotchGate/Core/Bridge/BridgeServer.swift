import Foundation
import NotchGateKit
import os

/// Listens on the NotchGate Unix socket and hands decoded hook messages to
/// the main actor.
final class BridgeServer: @unchecked Sendable {
    typealias MessageHandler = @MainActor (BridgeRequest, DecisionResponder) -> Void
    typealias DisconnectHandler = @MainActor (UUID) -> Void

    private let socketURL: URL
    private let queue = DispatchQueue(label: "notchgate.bridge.server")
    private var listener: UnixSocket?
    private var acceptSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: BridgeConnection] = [:]

    private let onMessage: MessageHandler
    private let onDisconnect: DisconnectHandler

    init(
        socketURL: URL = BridgeLocation.socketURL,
        onMessage: @escaping MessageHandler,
        onDisconnect: @escaping DisconnectHandler
    ) {
        self.socketURL = socketURL
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    func start() throws {
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let listener = try UnixSocket.listen(at: socketURL)
        listener.setNonBlocking()

        let source = DispatchSource.makeReadSource(fileDescriptor: listener.fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { listener.close() }
        source.resume()

        self.listener = listener
        self.acceptSource = source
        Log.bridge.info("Listening on \(self.socketURL.path, privacy: .public)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listener = nil
        unlink(socketURL.path)
    }

    // MARK: Private

    private func acceptPending() {
        guard let listener else { return }
        while let client = try? listener.accept() {
            let connection = BridgeConnection(
                socket: client,
                // Both callbacks hop via the main queue (not `Task`) so delivery is
                // strictly FIFO: a hang-up can never overtake its own request.
                onRequest: { [onMessage] request, connection in
                    DispatchQueue.main.async { MainActor.assumeIsolated { onMessage(request, connection) } }
                },
                onClose: { [weak self] connection, pendingID in
                    guard let self else { return }
                    queue.async { self.connections[ObjectIdentifier(connection)] = nil }
                    guard let pendingID else { return }
                    let onDisconnect = self.onDisconnect
                    DispatchQueue.main.async { MainActor.assumeIsolated { onDisconnect(pendingID) } }
                }
            )
            connections[ObjectIdentifier(connection)] = connection
            connection.start()
        }
    }
}
