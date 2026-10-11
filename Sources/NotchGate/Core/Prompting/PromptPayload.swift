import Foundation

/// A prompt made safe to type into a terminal.
///
/// Control characters are stripped so a message can never smuggle escape
/// sequences into the terminal. Multi-line prompts are delivered as a
/// bracketed paste so their newlines don't submit early; single lines are
/// typed exactly like keystrokes.
///
/// Attached images travel as file paths after the message, pasted the same
/// way a file dragged into the terminal arrives, so Claude Code picks them up.
struct PromptPayload: Equatable, Sendable {
    static let maxLength = 20_000
    static let pasteStart = "\u{1B}[200~"
    static let pasteEnd = "\u{1B}[201~"
    /// Return key. Sent separately, after a short pause, so Claude Code sees
    /// a key press rather than a newline inside pasted text.
    static let submitKey = "\r"
    static let submitDelay: Duration = .milliseconds(150)

    let text: String
    let hasImages: Bool

    var isMultiline: Bool { text.contains("\n") }

    /// Multi-line text and image paths go in as a bracketed paste.
    var isPasted: Bool { isMultiline || hasImages }

    /// What to write to the terminal before pressing Return.
    var typedText: String {
        isPasted ? Self.pasteStart + text + Self.pasteEnd : text
    }

    /// - Parameter images: attachment files; the prompt may be empty when there are some.
    init(_ raw: String, images: [URL] = []) throws(PromptDeliveryError) {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleaned = String(String.UnicodeScalarView(normalized.unicodeScalars.filter(Self.isAllowed)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = images.map(\.path).joined(separator: " ")
        let combined = [cleaned, paths].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !combined.isEmpty else { throw .emptyPrompt }
        guard combined.count <= Self.maxLength else { throw .tooLong(limit: Self.maxLength) }
        text = combined
        hasImages = !images.isEmpty
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A: return true                  // tab, newline
        case 0x00...0x1F, 0x7F, 0x80...0x9F: return false // C0, DEL, C1 controls
        default: return true
        }
    }
}
