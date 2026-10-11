import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@MainActor
@Suite("Dismissing a session")
struct SessionDismissTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ event: HookEvent, session: String = "s1", _ fields: [String: JSONValue] = [:]) -> BridgeRequest {
        var payload = fields
        payload["session_id"] = .string(session)
        payload["cwd"] = .string("/tmp/shop")
        return BridgeRequest(event: event, payload: .object(payload), origin: ProcessOrigin(claudePID: 0))
    }

    private func tracker(with sessions: [String]) -> ActivityTracker {
        let tracker = ActivityTracker(fileExists: { _ in false })
        for id in sessions { tracker.ingest(event(.userPromptSubmit, session: id), now: now) }
        return tracker
    }

    @Test func removesOnlyThatSession() {
        let tracker = tracker(with: ["s1", "s2"])
        tracker.dismiss("s1", now: now)
        #expect(tracker.sessions.keys.sorted() == ["s2"])
        #expect(tracker.dismissed.keys.contains("s1"))
    }

    @Test func staysHiddenWhileClaudeKeepsWorking() {
        let tracker = tracker(with: ["s1"])
        tracker.dismiss("s1", now: now)
        tracker.ingest(event(.preToolUse, ["tool_name": .string("Bash"), "tool_input": .object([:])]), now: now)
        tracker.ingest(event(.stop), now: now)
        tracker.ingest(event(.sessionStart, ["source": .string("compact")]), now: now)
        #expect(tracker.sessions["s1"] == nil)
    }

    @Test func comesBackWhenPromptedAgain() throws {
        let tracker = tracker(with: ["s1"])
        tracker.dismiss("s1", now: now)
        tracker.ingest(event(.userPromptSubmit, ["prompt": .string("one more thing")]), now: now)
        let session = try #require(tracker.sessions["s1"])
        #expect(session.prompt == "one more thing")
        #expect(tracker.dismissed["s1"] == nil)
    }

    @Test func comesBackWhenStartedOver() {
        let tracker = tracker(with: ["s1"])
        tracker.dismiss("s1", now: now)
        tracker.ingest(event(.sessionStart, ["source": .string("clear")]), now: now)
        #expect(tracker.sessions["s1"] != nil)
    }

    @Test func endingTheSessionForgetsTheDismissal() {
        let tracker = tracker(with: ["s1"])
        tracker.dismiss("s1", now: now)
        tracker.ingest(event(.sessionEnd), now: now)
        #expect(tracker.dismissed.isEmpty)
        #expect(tracker.sessions.isEmpty)
    }

    @Test func pruneForgetsLongQuietDismissals() {
        let tracker = tracker(with: ["s1"])
        tracker.dismiss("s1", now: now)
        tracker.prune(now: now.addingTimeInterval(ActivityTracker.staleAfter + 1))
        #expect(tracker.dismissed.isEmpty)
    }

    @Test func viewModelReleasesTheSessionsCardsAndQueuedPrompt() {
        let store = RequestStore()
        let tracker = tracker(with: ["demo-docs"])
        let model = IslandViewModel(
            store: store,
            settings: AppSettings(defaults: UserDefaults(suiteName: "dismiss-\(UUID().uuidString)")!),
            activity: tracker
        )
        store.enqueue(DemoRequests.make(.permission, sessionID: "demo-docs"), responder: DemoResponder())
        store.sendPrompt("later", to: "demo-docs")
        #expect(store.queuedPrompts["demo-docs"] != nil)

        model.dismissSession("demo-docs")
        #expect(store.pendingRequest(for: "demo-docs") == nil)
        #expect(store.queuedPrompts["demo-docs"] == nil)
        #expect(tracker.sessions["demo-docs"] == nil)
    }
}
