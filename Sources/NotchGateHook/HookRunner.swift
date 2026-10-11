import Darwin
import Foundation
import NotchGateKit

/// Reads the hook payload from stdin, forwards it to the app, and prints
/// the decision in Claude Code's expected format.
struct HookRunner {
    private let client = BridgeClient(socketURL: BridgeLocation.socketURL)

    func run() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let payload = try? JSONDecoder().decode(JSONValue.self, from: input),
            let eventName = payload["hook_event_name"]?.stringValue
        else { return 0 }

        let event = HookEvent(rawValue: eventName)
        if CommandLine.arguments.contains("--rewake") {
            return event == .stop ? awaitFollowUp(payload) : 0
        }
        let request = BridgeRequest(
            event: event,
            payload: HookPolicy.sanitize(event: event, payload: payload),
            origin: ProcessOrigin(claudePID: getppid())
        )

        do {
            guard let reply = try client.exchange(request) else { return 0 }
            if let output = HookOutput.render(event: event, decision: reply.decision) {
                try emit(output)
            }
        } catch {
            debugLog("notchgate-hook: \(error)")
        }
        return 0
    }

    /// Runs in the background after Claude stops. If the user sends a prompt
    /// from the notch, print it and exit 2 so Claude wakes up and acts on it.
    private func awaitFollowUp(_ payload: JSONValue) -> Int32 {
        let request = BridgeRequest(
            event: .stopRewake,
            payload: HookPolicy.sanitize(event: .stop, payload: payload),
            origin: ProcessOrigin(claudePID: getppid())
        )
        guard let reply = try? client.exchange(request),
              let message = HookOutput.rewakeMessage(for: reply.decision) else { return 0 }
        FileHandle.standardError.write(Data(message.utf8))
        return HookOutput.rewakeExitCode
    }

    private func emit(_ output: JSONValue) throws {
        var data = try JSONEncoder.bridge.encode(output)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["NOTCHGATE_DEBUG"] != nil else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
