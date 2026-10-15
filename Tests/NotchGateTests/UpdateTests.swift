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

    @Test @MainActor func relaunchOnTheSameCommitReportsTheUpdateDidNotApply() throws {
        let defaults = try #require(UserDefaults(suiteName: "updates-\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        defaults.set("1111111aaaa", forKey: UpdateChecker.updateStartedFromKey)

        let checker = UpdateChecker(settings: settings, bundle: try appBundle(commit: "1111111aaaa"), defaults: defaults)
        guard case .failed(let message) = checker.state else {
            Issue.record("expected a failure, got \(checker.state)")
            return
        }
        #expect(message.contains("1111111"))
        #expect(defaults.string(forKey: UpdateChecker.updateStartedFromKey) == nil)
    }

    @Test @MainActor func relaunchOnANewCommitIsQuiet() throws {
        let defaults = try #require(UserDefaults(suiteName: "updates-\(UUID())"))
        defaults.set("1111111aaaa", forKey: UpdateChecker.updateStartedFromKey)

        let checker = UpdateChecker(settings: AppSettings(defaults: defaults), bundle: try appBundle(commit: "2222222bbbb"), defaults: defaults)
        #expect(checker.state == .idle)
        #expect(defaults.string(forKey: UpdateChecker.updateStartedFromKey) == nil)
    }

    /// A throwaway `NotchGate.app` whose Info.plist records `commit`, like `Scripts/bundle.sh` writes.
    private func appBundle(commit: String) throws -> Bundle {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID())/NotchGate.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.notchgate.\(UUID())", "NotchGateCommit": commit]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: app))
    }

    @Test @MainActor func devBuildsDontCheckForUpdates() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "updates-\(UUID())") ?? .standard)
        let checker = UpdateChecker(settings: settings, bundle: .main) // swift test runs outside an .app
        #expect(checker.state == .unsupported)
        #expect(checker.installedCommit == nil)
    }

    @Test @MainActor func devBuildsDontCheckWhenTheMenuOpens() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "updates-\(UUID())") ?? .standard)
        let checker = UpdateChecker(settings: settings, bundle: .main)
        checker.checkOnMenuOpen()
        #expect(checker.state == .unsupported)
    }

    @Test func openingTheMenuRechecksAtMostEveryTenMinutes() {
        let now = Date()
        #expect(UpdateChecker.isDueOnMenuOpen(lastCheckedAt: nil, now: now))
        #expect(!UpdateChecker.isDueOnMenuOpen(lastCheckedAt: now.addingTimeInterval(-60), now: now))
        #expect(!UpdateChecker.isDueOnMenuOpen(lastCheckedAt: now.addingTimeInterval(-9 * 60), now: now))
        #expect(UpdateChecker.isDueOnMenuOpen(lastCheckedAt: now.addingTimeInterval(-10 * 60), now: now))
    }
}
