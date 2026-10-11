import Foundation
import Testing
@testable import NotchGateKit

@Suite("Transport")
struct TransportTests {
    @Test func framerSplitsAcrossChunks() throws {
        var framer = LineFramer()
        #expect(try framer.append(Data("{\"a\":".utf8)).isEmpty)
        let frames = try framer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8))
        #expect(frames.map { String(decoding: $0, as: UTF8.self) } == ["{\"a\":1}", "{\"b\":2}"])
        #expect(try framer.append(Data(":3}\n".utf8)).count == 1)
    }

    @Test func jsonValueRoundTripsAndKeepsIntegersClean() throws {
        let source = #"{"timeout":3600,"ratio":0.5,"ok":true,"none":null,"list":["a",1],"nested":{"k":"v"}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
        let encoded = try JSONEncoder.bridge.encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == value)
        // Whole numbers must not gain a ".0" when we rewrite settings.json.
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"timeout\":3600"))
    }

    @Test func bridgeMessagesSurviveTheWire() throws {
        let request = BridgeRequest(
            event: .permissionRequest,
            payload: .object(["tool_name": .string("Bash")]),
            origin: ProcessOrigin(claudePID: 42)
        )
        #expect(request.expectsReply)
        let decoded = try JSONDecoder().decode(BridgeRequest.self, from: JSONEncoder.bridge.encode(request))
        #expect(decoded == request)

        let reply = BridgeReply(id: request.id, decision: .deny(message: "no", interrupt: false))
        #expect(try JSONDecoder().decode(BridgeReply.self, from: JSONEncoder.bridge.encode(reply)) == reply)
    }

    @Test func socketRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ng-\(UUID().uuidString.prefix(8)).sock")
        let listener = try UnixSocket.listen(at: url)
        defer { listener.close(); unlink(url.path) }

        let client = try UnixSocket.connect(to: url)
        defer { client.close() }
        let server = try listener.accept()
        defer { server.close() }

        let request = BridgeRequest(event: .stop, payload: .object([:]), origin: ProcessOrigin(claudePID: 1))
        try client.sendFrame(request)
        #expect(try server.receiveFrame(BridgeRequest.self) == request)

        try server.sendFrame(BridgeReply(id: request.id, decision: .continueSession(prompt: "go")))
        #expect(try client.receiveFrame(BridgeReply.self).decision == .continueSession(prompt: "go"))
    }

    @Test func unknownEventsDecodeAndDoNotBlock() throws {
        let event = try JSONDecoder().decode(HookEvent.self, from: Data(#""SomeFutureEvent""#.utf8))
        #expect(event.rawValue == "SomeFutureEvent")
        #expect(!event.expectsReply)
    }
}
