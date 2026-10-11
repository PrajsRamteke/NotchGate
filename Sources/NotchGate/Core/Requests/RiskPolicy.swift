import Foundation
import NotchGateKit

/// Recognises commands that are destructive or hard to undo, so auto-allow
/// can still stop and ask for them.
enum RiskPolicy {
    /// Case-insensitive patterns matched against a Bash command.
    static let riskyCommandPatterns: [String] = [
        #"\brm\s+(-[a-z]*[rf][a-z]*\s+)+"#,          // rm -rf, rm -r, rm -f
        #"\bsudo\b"#,
        #"\bgit\s+push\b.*(--force|\s-f\b|--force-with-lease)"#,
        #"\bgit\s+reset\s+--hard\b"#,
        #"\bgit\s+clean\s+-[a-z]*f"#,
        #"\bgit\s+branch\s+-D\b"#,
        #"\b(mkfs|diskutil\s+erase|fdisk)\b"#,
        #"\bdd\s+if="#,
        #"\bchmod\s+(-R\s+)?777\b"#,
        #"\b(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z)?sh\b"#,
        #"\bdrop\s+(table|database|schema)\b"#,
        #"\btruncate\s+table\b"#,
        #":\(\)\s*\{\s*:\|:&\s*\};:"#,                // fork bomb
    ]

    private static let regexes: [NSRegularExpression] = riskyCommandPatterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    static func isRisky(_ permission: ToolPermission) -> Bool {
        guard permission.toolName == "Bash", let command = permission.input["command"]?.stringValue else {
            return false
        }
        return isRisky(command: command)
    }

    static func isRisky(command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return regexes.contains { $0.firstMatch(in: command, range: range) != nil }
    }
}
