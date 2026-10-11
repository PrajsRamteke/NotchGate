import Foundation

/// Reads the tail of the installer's log so the menu can show what the update is doing.
enum UpdateLog {
    /// The installer colours its output with ANSI escapes (`ESC[32m`); the menu shows plain text.
    private static let ansiEscapePattern = "\u{1B}\\[[0-9;]*[A-Za-z]"

    /// The last `count` non-empty lines of the log, without colour codes.
    static func recentLines(_ count: Int = 6) -> [String] {
        guard let text = try? String(contentsOf: Updater.logURL, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: ansiEscapePattern, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }
}
