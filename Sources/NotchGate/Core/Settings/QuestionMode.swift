import Foundation

/// How Claude's `AskUserQuestion` prompts are handled.
enum QuestionMode: String, CaseIterable, Identifiable, Sendable {
    /// Answer from the notch card.
    case notch
    /// Answer in Claude Code's terminal UI; the notch only alerts you.
    case terminal
    /// Tell Claude not to ask: it picks the most reasonable option and continues.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "Notch"
        case .terminal: return "Terminal"
        case .off: return "Don't ask"
        }
    }

    /// Every mode at once, for the setting's ⓘ.
    static let explanation = """
    How Claude's multiple-choice questions reach you.

    **Notch**: answer from the notch card.
    **Terminal**: answer in Claude Code; the notch only alerts you.
    **Don't ask**: Claude picks the most sensible option and keeps going.
    """

    /// What Claude is told when questions are turned off.
    static let declineMessage = """
    The user has turned off questions. Do not ask them anything. Choose the most \
    reasonable option yourself, briefly state the assumption you made, and continue.
    """
}
