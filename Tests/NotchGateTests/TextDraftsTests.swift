import Foundation
import Testing
@testable import NotchGate

@Suite("Unsent prompt text")
@MainActor
struct TextDraftsTests {
    @Test func eachSessionKeepsItsOwnText() {
        let drafts = TextDrafts()
        drafts.set("fix the flaky test", for: "s1")
        drafts.set("bump deps", for: "s2")
        #expect(drafts.text(for: "s1") == "fix the flaky test")
        #expect(drafts.text(for: "s2") == "bump deps")
        #expect(drafts.text(for: "s3") == "")
    }

    @Test func blankTextIsNotADraft() {
        let drafts = TextDrafts()
        drafts.set("  \n ", for: "s1")
        #expect(!drafts.hasDraft(for: "s1"))
        drafts.set("ok", for: "s1")
        #expect(drafts.hasDraft(for: "s1"))
        drafts.set("", for: "s1")
        #expect(drafts.texts["s1"] == nil)
    }

    @Test func outlivesTheComposerAndClearsOnRequest() {
        let controller = ComposerController(store: RequestStore(), activity: ActivityTracker())
        controller.texts.set("half-written prompt", for: "s1")
        // A new composer for the same session (the island reopened) finds it waiting.
        #expect(controller.texts.text(for: "s1") == "half-written prompt")
        controller.texts.clear("s1")
        #expect(!controller.texts.hasDraft(for: "s1"))
    }
}
