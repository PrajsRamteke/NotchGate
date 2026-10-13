import Foundation
import NotchGateKit

/// Types into a VS Code-family integrated terminal (Cursor, VS Code, Windsurf,
/// VSCodium) through the NotchGate Bridge extension.
///
/// Every editor window running the extension listens on its own socket in
/// `editors/`. We ask each in turn; the window owning a terminal whose shell
/// is an ancestor of the Claude process types the text and answers `ok`.
enum EditorBridgeTyper {
    static var directory: URL { BridgeLocation.supportDirectory.appendingPathComponent("editors", isDirectory: true) }

    struct Request: Encodable {
        let type: String
        let pids: [Int32]
        var text: String = ""
        var submit = true
        var submitDelayMs = 150
    }

    struct Response: Decodable {
        let ok: Bool
        let error: String?
        let message: String?
    }

    /// Editor windows with the extension active right now.
    static var connectedSockets: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "sock" }
    }

    static func type(_ payload: PromptPayload, editor: String, processIDs: [Int32]) async throws(PromptDeliveryError) {
        let request = Request(type: "send", pids: processIDs, text: payload.typedText,
                              submitDelayMs: payload.submitDelayMilliseconds)
        try await deliver(request, editor: editor)
    }

    /// Presses Return alone. An empty `send` does that (older helpers refuse it as a bad request).
    static func pressReturn(editor: String, processIDs: [Int32]) async throws(PromptDeliveryError) {
        try await deliver(Request(type: "send", pids: processIDs), editor: editor)
    }

    private static func deliver(_ request: Request, editor: String) async throws(PromptDeliveryError) {
        let sockets = connectedSockets
        guard !sockets.isEmpty else { throw .editorHelperMissing(editor) }

        var reachedAnyWindow = false
        for socket in sockets {
            switch await exchange(request, with: socket) {
            case .some(let response) where response.ok:
                return
            case .some(let response):
                reachedAnyWindow = true
                if response.error != "no-terminal" {
                    throw .commandFailed(response.message ?? response.error ?? "\(editor) refused the text")
                }
            case .none:
                try? FileManager.default.removeItem(at: socket) // Stale: that window is gone.
            }
        }
        throw reachedAnyWindow ? .targetNotFound("terminal in \(editor)") : .editorHelperMissing(editor)
    }

    /// Whether some editor window can see a terminal for these processes (no typing).
    static func canReach(processIDs: [Int32]) async -> Bool {
        for socket in connectedSockets {
            if await exchange(Request(type: "find", pids: processIDs), with: socket)?.ok == true { return true }
        }
        return false
    }

    /// One request/response over a window's socket; `nil` if the window is unreachable.
    private static func exchange(_ request: Request, with socket: URL) async -> Response? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let connection = try? UnixSocket.connect(to: socket) else {
                    return continuation.resume(returning: nil)
                }
                defer { connection.close() }
                connection.setReceiveTimeout(seconds: 3)
                guard (try? connection.sendFrame(request)) != nil else { return continuation.resume(returning: nil) }
                continuation.resume(returning: try? connection.receiveFrame(Response.self))
            }
        }
    }
}
