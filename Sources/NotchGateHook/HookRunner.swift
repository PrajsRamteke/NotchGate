import Darwin
import Foundation
import NotchGateKit

/// Reads the hook payload from stdin, forwards it to the app, and prints
/// the decision in Claude Code's expected format.
struct HookRunner {
    /// `PreToolUse` is only used to answer interactive tools; everything else
    /// passes straight through without touching the socket.
    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    private let client = BridgeClient(socketURL: BridgeLocation.socketURL)

    func run() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let payload = try? JSONDecoder().decode(JSONValue.self, from: input),
            let eventName = payload["hook_event_name"]?.stringValue
        else { return 0 }

        let event = HookEvent(rawValue: eventName)
        guard shouldForward(event: event, payload: payload) else { return 0 }

        let request = BridgeRequest(
            event: event,
            payload: event == .postToolUse ? payload.removing("tool_response") : payload,
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

    private func shouldForward(event: HookEvent, payload: JSONValue) -> Bool {
        guard event == .preToolUse else { return true }
        let tool = payload["tool_name"]?.stringValue ?? ""
        return Self.interactiveTools.contains(tool)
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
