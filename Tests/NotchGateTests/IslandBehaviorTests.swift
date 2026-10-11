import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Island stays open while engaged")
@MainActor
struct IslandBehaviorTests {
    private func makeModel() -> IslandViewModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "island-\(UUID())") ?? .standard)
        return IslandViewModel(store: RequestStore(), settings: settings, activity: ActivityTracker())
    }

    private func permission() -> ClaudeRequest {
        ClaudeRequest(
            id: UUID(), event: .permissionRequest,
            session: SessionInfo(id: "s1", cwd: "/tmp/app", claudePID: 1),
            kind: .permission(ToolPermission(toolName: "Bash", input: .object([:]), suggestions: []))
        )
    }

    @Test func minimizingWhileHoveredKeepsTheIslandOpen() {
        let model = makeModel()
        model.store.enqueue(permission(), responder: DemoResponder())
        model.setHovering(true)

        model.collapse()

        #expect(model.presentation == .expanded)
        #expect(model.isRequestMinimized)
        #expect(model.isShowingActivity)

        model.expand()
        #expect(!model.isRequestMinimized)
    }

    @Test func minimizedRequestBecomesAPeekOnceTheCursorLeaves() {
        let model = makeModel()
        model.store.enqueue(permission(), responder: DemoResponder())
        model.setHovering(true)
        model.collapse()
        model.setHovering(false)
        #expect(model.presentation == .peek)
    }

    @Test func answeringACardWhileHoveredShowsActivityInsteadOfClosing() {
        let model = makeModel()
        model.store.enqueue(permission(), responder: DemoResponder())
        model.setHovering(true)

        model.respond(.allow())

        #expect(model.presentation == .expanded)
        #expect(model.isShowingActivity)
    }

    @Test func toggleShortcutAlternatesCardAndMinimized() {
        let model = makeModel()
        model.store.enqueue(permission(), responder: DemoResponder())
        model.setHovering(true)
        model.toggle()
        #expect(model.isRequestMinimized)
        model.toggle()
        #expect(!model.isRequestMinimized)
    }
}
