import Foundation
import Testing
@testable import NotchGate

@Suite("Updates")
struct UpdateTests {
    @Test func parsesCompareResponseNewestFirst() {
        let json: [String: Any] = [
            "status": "ahead", "ahead_by": 2,
            "commits": [
                ["sha": "1111111aaaa", "commit": ["message": "Older change\n\nDetails"]],
                ["sha": "2222222bbbb", "commit": ["message": "Newest change"]],
            ],
        ]
        let info = UpdateSource.info(fromCompare: json, installedSHA: "0000000")
        #expect(info.aheadBy == 2)
        #expect(info.latestSHA == "2222222bbbb")
        #expect(info.commits.map(\.title) == ["Newest change", "Older change"])
        #expect(info.commits.first?.shortSHA == "2222222")
    }

    @Test func upToDateWhenNothingIsAhead() {
        let info = UpdateSource.info(fromCompare: ["status": "identical", "ahead_by": 0, "commits": []], installedSHA: "abc")
        #expect(info.aheadBy == 0)
        #expect(info.latestSHA == "abc")
    }

    @Test @MainActor func devBuildsDontCheckForUpdates() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "updates-\(UUID())") ?? .standard)
        let checker = UpdateChecker(settings: settings, bundle: .main) // swift test runs outside an .app
        #expect(checker.state == .unsupported)
        #expect(checker.installedCommit == nil)
    }
}
