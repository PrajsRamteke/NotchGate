import Foundation
import NotchGateKit

/// One hook process connected over the socket.
///
/// All mutable state is confined to `queue`, which is why the type can be
/// `@unchecked Sendable`. The connection stays open while the hook waits, so a
/// peer hang-up tells us the request was answered elsewhere.
final class BridgeConnection: DecisionResponder, @unchecked Sendable {
    typealias RequestHandler = @Sendable (BridgeRequest, BridgeConnection) -> Void
    typealias CloseHandler = @Sendable (BridgeConnection, _ pendingRequestID: UUID?) -> Void

    private let socket: UnixSocket
    private let queue: DispatchQueue
    private var source: DispatchSourceRead?
    private var framer = LineFramer()
    private var request: BridgeRequest?
    private var isFinished = false

    private let onRequest: RequestHandler
    private let onClose: CloseHandler

    init(socket: UnixSocket, onRequest: @escaping RequestHandler, onClose: @escaping CloseHandler) {
        self.socket = socket
        self.queue = DispatchQueue(label: "notchgate.bridge.connection")
        self.onRequest = onRequest
        self.onClose = onClose
    }

    func start() {
        socket.setNonBlocking()
        let source = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [socket] in socket.close() }
        self.source = source
        source.resume()
    }

    // MARK: DecisionResponder

    func send(_ decision: BridgeDecision) {
        queue.async { [self] in
            guard !isFinished, let request, request.expectsReply else { return }
            try? socket.sendFrame(BridgeReply(id: request.id, decision: decision))
            finish(notify: false)
        }
    }

    // MARK: Reading

    private func readAvailable() {
        do {
            let chunk = try socket.receive()
            guard !chunk.isEmpty else { return finish(notify: true) } // EOF
            guard request == nil else { return } // Only one request per connection.
            guard let frame = try framer.append(chunk).first else { return }

            let message = try JSONDecoder().decode(BridgeRequest.self, from: frame)
            guard message.version == BridgeRequest.currentVersion else { return finish(notify: false) }
            request = message
            onRequest(message, self)
            if !message.expectsReply { finish(notify: false) }
        } catch SocketError.timedOut {
            return // Spurious wake-up on a non-blocking socket.
        } catch {
            finish(notify: true)
        }
    }

    private func finish(notify: Bool) {
        guard !isFinished else { return }
        isFinished = true
        source?.cancel()
        source = nil
        let pendingID = (notify && request?.expectsReply == true) ? request?.id : nil
        onClose(self, pendingID)
    }
}
