import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("HookSettingsEditor")
struct HookSettingsEditorTests {
    private let editor = HookSettingsEditor(hookPath: "/Users/me/.notchgate/bin/notchgate-hook")

    private var existing: JSONValue {
        .object([
            "model": .string("opus"),
            "hooks": .object([
                "Stop": .array([.object(["hooks": .array([.object([
                    "type": .string("command"), "command": .string("python3 other.py"),
                ])])])]),
            ]),
        ])
    }

    @Test func installAddsEveryEventAndKeepsOtherSettings() {
        let installed = editor.installing(into: existing)
        #expect(editor.isInstalled(in: installed))
        #expect(installed["model"] == .string("opus"))
        // The user's own Stop hook survives alongside ours.
        #expect(installed["hooks"]?["Stop"]?.arrayValue?.count == 2)
        #expect(installed["hooks"]?["PreToolUse"]?.arrayValue?.first?["matcher"] == .string("*"))
    }

    @Test func installIsIdempotent() {
        let once = editor.installing(into: existing)
        let twice = editor.installing(into: once)
        #expect(once == twice)
        #expect(editor.isCurrent(in: once))
    }

    @Test func detectsOutdatedInstallsForUpgrade() {
        let legacy = existing.setting("hooks", to: .object([
            "PreToolUse": .array([.object([
                "matcher": .string("AskUserQuestion|ExitPlanMode"),
                "hooks": .array([.object(["type": .string("command"), "command": .string("\"/x/notchgate-hook\"")])]),
            ])]),
        ]))
        #expect(editor.hasAnyHook(in: legacy))
        #expect(!editor.isCurrent(in: legacy))
        #expect(!editor.hasAnyHook(in: existing))
    }

    @Test func uninstallRestoresOriginalHooks() {
        let roundTrip = editor.uninstalling(from: editor.installing(into: existing))
        #expect(roundTrip == existing)
        #expect(!editor.isInstalled(in: roundTrip))
    }

    @Test func reportsOnlyForeignPermissionHooks() {
        let foreign = existing.setting("hooks", to: .object([
            "PermissionRequest": .array([.object(["hooks": .array([.object([
                "type": .string("command"), "command": .string("python3 island.py"),
            ])])])]),
        ]))
        #expect(editor.conflictingCommands(in: editor.installing(into: foreign)) == ["python3 island.py"])
        #expect(editor.conflictingCommands(in: editor.installing(into: existing)).isEmpty)
    }

    @Test func installIntoEmptySettings() {
        let installed = editor.installing(into: .object([:]))
        #expect(editor.isInstalled(in: installed))
        #expect(installed["hooks"]?.objectValue?.count == HookSettingsEditor.registrations.count)
    }
}
