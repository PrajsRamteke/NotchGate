import Foundation
import Testing
@testable import NotchGate

@Suite("Bridge socket")
struct BridgeServerSocketTests {
    private func socketURL() -> URL {
        // Unix socket paths are capped at 104 bytes; keep it short.
        URL(fileURLWithPath: "/tmp/ng-\(UUID().uuidString.prefix(8)).sock")
    }

    private func server(at url: URL) -> BridgeServer {
        BridgeServer(socketURL: url, onMessage: { _, _ in }, onDisconnect: { _ in })
    }

    @Test func quittingInstanceLeavesTheNewInstancesSocket() throws {
        let url = socketURL()
        defer { unlink(url.path) }
        let old = server(at: url)
        try old.start()
        let new = server(at: url)
        try new.start()

        old.stop()
        #expect(FileManager.default.fileExists(atPath: url.path))

        new.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func restoresARemovedSocket() async throws {
        let url = socketURL()
        let bridge = server(at: url)
        try bridge.start()
        defer { bridge.stop() }

        unlink(url.path)
        try await Task.sleep(for: .seconds(4))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
