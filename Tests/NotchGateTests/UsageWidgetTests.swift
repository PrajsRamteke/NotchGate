import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Usage widget")
struct UsageWidgetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func statusLine(_ limits: JSONValue?) -> JSONValue {
        var input: [String: JSONValue] = ["model": .object(["display_name": .string("Opus")])]
        if let limits { input["rate_limits"] = limits }
        return .object(input)
    }

    private func window(_ used: Double, resetsIn seconds: Double) -> JSONValue {
        .object([
            "used_percentage": .number(used),
            "resets_at": .number(now.timeIntervalSince1970 + seconds),
        ])
    }

    // MARK: Snapshot

    @Test func readsBothWindowsFromTheStatusLine() throws {
        let input = statusLine(.object([
            "five_hour": window(23.5, resetsIn: 3600),
            "seven_day": window(41.2, resetsIn: 86_400 * 3),
        ]))
        let snapshot = try #require(UsageSnapshot(statusLine: input, now: now))
        #expect(snapshot.fiveHour?.usedPercentage == 23.5)
        #expect(snapshot.fiveHour?.resetsAt == now.addingTimeInterval(3600))
        #expect(snapshot.sevenDay?.usedPercentage == 41.2)
        #expect(snapshot.updatedAt == now)
    }

    @Test func noRateLimitsMeansNoSnapshot() {
        // API-key users, or before the session's first reply: keep the last numbers.
        #expect(UsageSnapshot(statusLine: statusLine(nil), now: now) == nil)
    }

    @Test func aMissingWindowHasReset() throws {
        let input = statusLine(.object(["seven_day": window(10, resetsIn: 600)]))
        let snapshot = try #require(UsageSnapshot(statusLine: input, now: now))
        #expect(snapshot.fiveHour == nil)
        #expect(UsageGauge.fiveHour(snapshot, now: now).resetText == "Fresh window")
    }

    @Test func clampsOutOfRangePercentages() throws {
        let input = statusLine(.object(["five_hour": window(130, resetsIn: 60)]))
        #expect(try #require(UsageSnapshot(statusLine: input, now: now)).fiveHour?.usedPercentage == 100)
    }

    @Test func savesAndLoadsTheSnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = UsageSnapshot(
            fiveHour: .init(usedPercentage: 12, resetsAt: now.addingTimeInterval(100)),
            sevenDay: nil,
            updatedAt: now
        )
        try snapshot.save(to: url)
        #expect(UsageSnapshot.load(from: url) == snapshot)
    }

    // MARK: Gauge

    @Test func gaugeShowsPercentLevelAndCountdown() {
        let gauge = UsageGauge(title: "5-hour limit", window: .init(usedPercentage: 76.4, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)), now: now)
        #expect(gauge.percent == 76)
        #expect(gauge.level == .high)
        #expect(gauge.resetText == "Resets in 2h 14m")
    }

    @Test func aWindowPastItsResetReadsAsFresh() {
        let gauge = UsageGauge(title: "Weekly limit", window: .init(usedPercentage: 95, resetsAt: now.addingTimeInterval(-1)), now: now)
        #expect(gauge.percent == 0)
        #expect(gauge.level == .normal)
        #expect(gauge.resetText == "Fresh window")
    }

    @Test func resetPhrases() {
        #expect(UsageGauge.resetPhrase(until: now.addingTimeInterval(20), now: now) == "Resets in 1m")
        #expect(UsageGauge.resetPhrase(until: now, now: now) == "Resets in under a minute")
        #expect(UsageGauge.resetPhrase(until: now.addingTimeInterval(42 * 60), now: now) == "Resets in 42m")
        #expect(UsageGauge.resetPhrase(until: now.addingTimeInterval(3 * 3600), now: now) == "Resets in 3h")
        #expect(UsageGauge.resetPhrase(until: now.addingTimeInterval(3 * 86_400), now: now).hasPrefix("Resets "))
        #expect(UsageGauge.updatedPhrase(now.addingTimeInterval(-30), now: now) == "Updated just now")
        #expect(UsageGauge.updatedPhrase(now.addingTimeInterval(-4 * 60), now: now) == "Updated 4m ago")
        #expect(UsageGauge.updatedPhrase(now.addingTimeInterval(-2 * 3600), now: now) == "Updated 2h ago")
    }
}

@Suite("Status line relay settings")
struct StatusLineSettingsEditorTests {
    private let editor = StatusLineSettingsEditor(hookPath: "/Users/me/.notchgate/bin/notchgate-hook")

    private var withOwnStatusLine: JSONValue {
        .object([
            "model": .string("opus"),
            "statusLine": .object([
                "type": .string("command"),
                "command": .string("~/.claude/statusline.sh"),
                "padding": .number(2),
            ]),
        ])
    }

    @Test func installWithoutAStatusLineAddsTheRelay() {
        let (settings, original) = editor.installing(into: .object(["model": .string("opus")]), keeping: nil)
        #expect(editor.isInstalled(in: settings))
        #expect(original == nil)
        #expect(settings["statusLine"]?["type"] == .string("command"))
        #expect(settings["statusLine"]?["command"] == .string(editor.command))
        #expect(settings["model"] == .string("opus"))
    }

    @Test func installKeepsTheUsersStatusLineAndItsOptions() {
        let (settings, original) = editor.installing(into: withOwnStatusLine, keeping: nil)
        #expect(original?["command"] == .string("~/.claude/statusline.sh"))
        #expect(settings["statusLine"]?["command"] == .string(editor.command))
        #expect(settings["statusLine"]?["padding"] == .number(2))
    }

    @Test func reinstallingKeepsTheSavedOriginal() {
        let first = editor.installing(into: withOwnStatusLine, keeping: nil)
        let second = editor.installing(into: first.settings, keeping: first.original)
        #expect(second.settings == first.settings)
        #expect(second.original == first.original)
    }

    @Test func uninstallRestoresTheUsersCommand() {
        let installed = editor.installing(into: withOwnStatusLine, keeping: nil)
        #expect(editor.uninstalling(from: installed.settings, original: installed.original) == withOwnStatusLine)
    }

    @Test func uninstallRemovesTheRelayWhenThereWasNoStatusLine() {
        let bare: JSONValue = .object(["model": .string("opus")])
        let installed = editor.installing(into: bare, keeping: nil)
        #expect(editor.uninstalling(from: installed.settings, original: nil) == bare)
    }

    @Test func uninstallLeavesAReplacedStatusLineAlone() {
        // The user set a new status line while the widget was on.
        #expect(editor.uninstalling(from: withOwnStatusLine, original: nil) == withOwnStatusLine)
    }

    @Test func installerRoundTripsThroughFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("statusline-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A stand-in hook binary, so nothing is copied from the app bundle.
        let hook = directory.appendingPathComponent("notchgate-hook")
        FileManager.default.createFile(atPath: hook.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        let settingsFile = ClaudeSettingsFile(url: directory.appendingPathComponent("settings.json"))
        try settingsFile.write(withOwnStatusLine)

        let installer = StatusLineInstaller(
            settingsFile: settingsFile,
            binary: HookBinary(installedURL: hook),
            originalURL: directory.appendingPathComponent("statusline-original.json")
        )
        try installer.install()
        #expect(installer.isInstalled)
        #expect(FileManager.default.fileExists(atPath: installer.originalURL.path))

        try installer.uninstall()
        #expect(!installer.isInstalled)
        #expect(try settingsFile.read() == withOwnStatusLine)
        #expect(!FileManager.default.fileExists(atPath: installer.originalURL.path))
    }
}
