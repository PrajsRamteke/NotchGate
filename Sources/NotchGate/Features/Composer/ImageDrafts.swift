import Foundation
import Observation

/// Images attached to each session's next prompt. Lives outside the composer
/// view so an image dropped on a project row is waiting there when its
/// composer opens, and survives the island closing.
@MainActor
@Observable
final class ImageDrafts {
    /// Claude Code takes many images per prompt; this keeps the notch tidy.
    static let limit = 10

    private(set) var images: [String: [ImageAttachment]] = [:]

    func images(for sessionID: String) -> [ImageAttachment] {
        images[sessionID] ?? []
    }

    /// Room left before the session hits `limit`.
    func remaining(for sessionID: String) -> Int {
        max(0, Self.limit - images(for: sessionID).count)
    }

    func add(_ attachments: [ImageAttachment], to sessionID: String) {
        let accepted = attachments.prefix(remaining(for: sessionID))
        guard !accepted.isEmpty else { return }
        images[sessionID, default: []].append(contentsOf: accepted)
    }

    func remove(_ attachment: ImageAttachment, from sessionID: String) {
        images[sessionID]?.removeAll { $0.id == attachment.id }
        if images[sessionID]?.isEmpty == true { images[sessionID] = nil }
        try? FileManager.default.removeItem(at: attachment.url)
    }

    /// Discards a session's unsent images and their files.
    func clear(_ sessionID: String) {
        for attachment in images.removeValue(forKey: sessionID) ?? [] {
            try? FileManager.default.removeItem(at: attachment.url)
        }
    }

    /// Forgets images once they've been sent (the files stay for Claude to read).
    /// Anything attached while the prompt was on its way stays put.
    func markSent(_ sent: [ImageAttachment], for sessionID: String) {
        let ids = Set(sent.map(\.id))
        images[sessionID]?.removeAll { ids.contains($0.id) }
        if images[sessionID]?.isEmpty == true { images[sessionID] = nil }
    }
}
