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
    /// The socket file this server created, so it never deletes another instance's.
    private var socketInode: ino_t?
    private var watchdog: DispatchSourceTimer?

    /// How often to check that the socket file is still there.
    static let watchdogInterval: DispatchTimeInterval = .seconds(3)

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
        try queue.sync { try listen() }

        let watchdog = DispatchSource.makeTimerSource(queue: queue)
        watchdog.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        watchdog.setEventHandler { [weak self] in self?.restoreSocketIfRemoved() }
        watchdog.resume()
        self.watchdog = watchdog
    }

    func stop() {
        queue.sync {
            watchdog?.cancel()
            watchdog = nil
            acceptSource?.cancel()
            acceptSource = nil
            listener = nil
            // Only remove our own socket: when NotchGate is relaunched, the new
            // instance may already be listening at this path.
            if let socketInode, Self.inode(at: socketURL.path) == socketInode {
                unlink(socketURL.path)
            }
            socketInode = nil
        }
    }

    // MARK: Private

    /// Binds the socket and starts accepting. Runs on `queue`.
    private func listen() throws {
        acceptSource?.cancel()
        let listener = try UnixSocket.listen(at: socketURL)
        listener.setNonBlocking()

        let source = DispatchSource.makeReadSource(fileDescriptor: listener.fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { listener.close() }
        source.resume()

        self.listener = listener
        self.acceptSource = source
        socketInode = Self.inode(at: socketURL.path)
        Log.bridge.info("Listening on \(self.socketURL.path, privacy: .public)")
    }

    /// Hooks reach the app by the socket's path, so if the file disappears
    /// while we're listening (an older instance quitting deleted it), every
    /// hook would fail. Put it back. Runs on `queue`.
    private func restoreSocketIfRemoved() {
        guard listener != nil, Self.inode(at: socketURL.path) == nil else { return }
        do {
            try listen()
            Log.bridge.notice("Socket file was removed; listening again")
        } catch {
            Log.bridge.error("Couldn't restore the socket: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func inode(at path: String) -> ino_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_ino : nil
    }

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
