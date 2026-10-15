import Foundation
import Observation

/// What's typed in each session's prompt box but not sent yet. Lives outside
/// the composer view, like `ImageDrafts`, so closing the island (clicking
/// elsewhere, moving the cursor away) doesn't throw the message away.
@MainActor
@Observable
final class TextDrafts {
    private(set) var texts: [String: String] = [:]

    func text(for sessionID: String) -> String {
        texts[sessionID] ?? ""
    }

    func set(_ text: String, for sessionID: String) {
        guard text != texts[sessionID, default: ""] else { return }
        texts[sessionID] = text.isEmpty ? nil : text
    }

    /// Something worth coming back for: not just spaces or newlines.
    func hasDraft(for sessionID: String) -> Bool {
        !(texts[sessionID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func clear(_ sessionID: String) {
        texts[sessionID] = nil
    }
}
