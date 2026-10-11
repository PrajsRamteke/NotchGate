import Foundation
import NotchGateKit

/// Blocking, single-shot client for the app's Unix socket.
struct BridgeClient {
    let socketURL: URL

    /// Sends `request` and, when the event expects one, waits for the reply.
    ///
    /// - Returns: `nil` when the app isn't running or no reply is expected.
    ///   No receive timeout is set on purpose: Claude Code enforces the hook
    ///   timeout and terminates us, which the app observes as a disconnect.
    func exchange(_ request: BridgeRequest) throws -> BridgeReply? {
        let socket: UnixSocket
        do {
            socket = try UnixSocket.connect(to: socketURL)
        } catch {
            return nil // App not running: fall back to the terminal UI.
        }
        defer { socket.close() }

        try socket.sendFrame(request)
        guard request.expectsReply else { return nil }

        let reply = try socket.receiveFrame(BridgeReply.self)
        return reply.id == request.id ? reply : nil
    }
}
