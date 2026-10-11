import Foundation

/// A prompt made safe to type into a terminal.
///
/// Control characters are stripped so a message can never smuggle escape
/// sequences into the terminal. Multi-line prompts are delivered as a
/// bracketed paste so their newlines don't submit early; single lines are
/// typed exactly like keystrokes.
struct PromptPayload: Equatable, Sendable {
    static let maxLength = 20_000
    static let pasteStart = "\u{1B}[200~"
    static let pasteEnd = "\u{1B}[201~"
    /// Return key. Sent separately, after a short pause, so Claude Code sees
    /// a key press rather than a newline inside pasted text.
    static let submitKey = "\r"
    static let submitDelay: Duration = .milliseconds(150)

    let text: String

    var isMultiline: Bool { text.contains("\n") }

    /// What to write to the terminal before pressing Return.
    var typedText: String {
        isMultiline ? Self.pasteStart + text + Self.pasteEnd : text
    }

    init(_ raw: String) throws(PromptDeliveryError) {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleaned = String(String.UnicodeScalarView(normalized.unicodeScalars.filter(Self.isAllowed)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw .emptyPrompt }
        guard cleaned.count <= Self.maxLength else { throw .tooLong(limit: Self.maxLength) }
        text = cleaned
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A: return true                  // tab, newline
        case 0x00...0x1F, 0x7F, 0x80...0x9F: return false // C0, DEL, C1 controls
        default: return true
        }
    }
}
