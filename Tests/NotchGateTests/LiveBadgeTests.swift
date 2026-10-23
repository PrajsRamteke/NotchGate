import Foundation
import Testing
@testable import NotchGate

@MainActor
@Suite("Live badge")
struct LiveBadgeTests {
    private func makeModel(liveBadge: Bool = true) -> IslandViewModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "live-badge-\(UUID())") ?? .standard)
        settings.liveInClosedNotch = liveBadge
        return IslandViewModel(store: RequestStore(), settings: settings, activity: ActivityTracker())
    }

    private func session(working: Bool) -> SessionActivity {
        var session = SessionActivity(id: "s1", cwd: "/tmp/app", claudePID: 0, updatedAt: .now)
        session.phase = working ? .thinking : .finished
        return session
    }

    @Test func aWorkingSessionWidensTheClosedNotch() {
        let model = makeModel()
        #expect(model.presentation == .hidden)

        model.activity.load([session(working: true)])
        #expect(model.showsLivePeek)
        #expect(model.presentation == .peek)

        model.activity.load([session(working: false)])
        #expect(!model.showsLivePeek)
        #expect(model.presentation == .hidden)
    }

    @Test func theClosedNotchStaysPlainWhenTurnedOff() {
        let model = makeModel(liveBadge: false)
        model.activity.load([session(working: true)])
        #expect(!model.showsLivePeek)
        #expect(model.presentation == .hidden)
    }

    @Test func claudeNeedingYouTakesPrecedence() {
        let model = makeModel()
        model.activity.load([session(working: true)])
        let info = SessionInfo(id: "s1", cwd: "/tmp/app", claudePID: 1)
        model.store.post(Notice(session: info, title: "Claude needs you", message: nil, tone: .attention))
        #expect(!model.showsLivePeek)
    }

    @Test func hoveringTheLiveBadgeStillWaitsForIntent() {
        let model = makeModel()
        model.activity.load([session(working: true)])
        model.setHovering(true)
        // The hover-intent delay hasn't passed: a sweep across the menu bar doesn't open it.
        #expect(model.presentation == .peek)
    }

    @Test func theSettingIsRemembered() {
        let defaults = UserDefaults(suiteName: "live-badge-\(UUID())") ?? .standard
        #expect(AppSettings(defaults: defaults).liveInClosedNotch)
        AppSettings(defaults: defaults).liveInClosedNotch = false
        #expect(!AppSettings(defaults: defaults).liveInClosedNotch)
    }
}
