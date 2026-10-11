import AppKit
import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Image attachments")
@MainActor
struct ImageAttachmentTests {
    private func pngData() throws -> Data {
        let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    private func scratchPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("notchgate-test-\(UUID())"))
        pasteboard.clearContents()
        return pasteboard
    }

    // MARK: Payload

    @Test func imagePathsFollowTheMessageAsAPaste() throws {
        let images = [URL(fileURLWithPath: "/tmp/NotchGate/Images/a1-shot.png"),
                      URL(fileURLWithPath: "/tmp/NotchGate/Images/b2-mock.jpg")]
        let payload = try PromptPayload("what's wrong here?", images: images)
        #expect(payload.text == "what's wrong here?\n\n/tmp/NotchGate/Images/a1-shot.png /tmp/NotchGate/Images/b2-mock.jpg")
        #expect(payload.isPasted)
        #expect(payload.typedText.hasPrefix(PromptPayload.pasteStart))
    }

    @Test func imagesCanBeSentWithoutAMessage() throws {
        let payload = try PromptPayload("  ", images: [URL(fileURLWithPath: "/tmp/x.png")])
        #expect(payload.text == "/tmp/x.png")
        #expect(payload.isPasted)
        #expect(throws: PromptDeliveryError.emptyPrompt) { try PromptPayload("  ", images: []) }
    }

    // MARK: Intake

    @Test func clipboardImagesBecomePNGFiles() throws {
        let pasteboard = scratchPasteboard()
        pasteboard.setData(try pngData(), forType: .png)

        #expect(ImageIntake.canRead(pasteboard))
        let attachments = ImageIntake.attachments(from: pasteboard)
        let attachment = try #require(attachments.first)
        #expect(attachments.count == 1)
        #expect(attachment.url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: attachment.url.path))
        #expect(!attachment.url.path.contains(" "))
        try? FileManager.default.removeItem(at: attachment.url)
    }

    @Test func plainTextIsLeftForTheTextField() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("just words", forType: .string)
        #expect(!ImageIntake.canRead(pasteboard))
        #expect(ImageIntake.attachments(from: pasteboard).isEmpty)
    }

    @Test func copiedImageFilesAreCopiedNotTheirIcons() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchgate test \(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("Screen Shot 1.png")
        let notes = folder.appendingPathComponent("notes.txt")
        try pngData().write(to: image)
        try Data("hi".utf8).write(to: notes)

        let pasteboard = scratchPasteboard()
        pasteboard.writeObjects([image as NSURL, notes as NSURL])
        let attachments = ImageIntake.attachments(from: pasteboard)
        let attachment = try #require(attachments.first)
        #expect(attachments.count == 1)
        #expect(attachment.url.lastPathComponent.hasSuffix("-Screen-Shot-1.png"))
        try? FileManager.default.removeItem(at: attachment.url)

        // A copied non-image file is never mistaken for an image (Finder adds its icon).
        let textOnly = scratchPasteboard()
        textOnly.writeObjects([notes as NSURL])
        textOnly.addTypes([.tiff], owner: nil)
        textOnly.setData(NSImage(size: CGSize(width: 4, height: 4)).tiffRepresentation ?? Data(), forType: .tiff)
        #expect(!ImageIntake.canRead(textOnly))
    }

    @Test func namesAreMadePathSafe() {
        #expect(ImageIntake.sanitizedName("Screen Shot 2026-10-11 at 4.05.12 PM") == "Screen-Shot-2026-10-11-at-4-05-12-PM")
        #expect(ImageIntake.sanitizedName("  ") == "image")
    }

    // MARK: Drafts

    @Test func draftsArePerSessionAndCapped() throws {
        let drafts = ImageDrafts()
        let make = { ImageAttachment(id: UUID(), url: URL(fileURLWithPath: "/tmp/none.png"), thumbnail: NSImage()) }
        drafts.add((0..<12).map { _ in make() }, to: "a")
        drafts.add([make()], to: "b")
        #expect(drafts.images(for: "a").count == ImageDrafts.limit)
        #expect(drafts.remaining(for: "a") == 0)
        #expect(drafts.images(for: "b").count == 1)

        let sent = Array(drafts.images(for: "a").prefix(3))
        drafts.markSent(sent, for: "a")
        #expect(drafts.images(for: "a").count == ImageDrafts.limit - 3)
        #expect(drafts.images(for: "b").count == 1)
    }

    // MARK: Island

    @Test func draggingImagesOverTheNotchShowsSessionsOverACard() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "drop-\(UUID())") ?? .standard)
        settings.showActivityOnHover = false
        let model = IslandViewModel(store: RequestStore(), settings: settings, activity: ActivityTracker())
        model.store.enqueue(ClaudeRequest(
            id: UUID(), event: .permissionRequest,
            session: SessionInfo(id: "s1", cwd: "/tmp/app", claudePID: 1),
            kind: .permission(ToolPermission(toolName: "Bash", input: .object([:]), suggestions: []))
        ), responder: DemoResponder())

        model.setDraggingImages(true)
        #expect(!model.isAcceptingDrop)
        model.showActivityNow()
        #expect(model.isAcceptingDrop)
        #expect(model.presentation == .expanded)
        #expect(model.isShowingActivity)

        model.attachImages([ImageAttachment(id: UUID(), url: URL(fileURLWithPath: "/tmp/none.png"), thumbnail: NSImage())], to: "s1")
        model.setDraggingImages(false)
        #expect(model.prompts.drafts.images(for: "s1").count == 1)
        #expect(model.presentation == .expanded) // still composing
        #expect(!model.isShowingActivity) // the waiting card is back
    }
}
