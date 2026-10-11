import Foundation

/// Files a session created, changed or deleted, shown on its row as
/// "+2 ~3 −1". Net per file: a file Claude creates and then deletes again
/// leaves no trace; one it deletes and recreates counts as changed.
struct FileChanges: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case added, modified, deleted
    }

    private(set) var files: [String: Kind] = [:]
    private(set) var linesAdded = 0
    private(set) var linesRemoved = 0

    var added: Int { count(.added) }
    var modified: Int { count(.modified) }
    var deleted: Int { count(.deleted) }
    var isEmpty: Bool { files.isEmpty }

    mutating func record(_ kind: Kind, path: String, linesAdded: Int = 0, linesRemoved: Int = 0) {
        let path = (path as NSString).standardizingPath
        let previous = files[path]
        switch (kind, previous) {
        case (.deleted, .added?): files[path] = nil
        case (.deleted, _): files[path] = .deleted
        case (_, .deleted?): files[path] = .modified
        case (_, .some): break // Added stays added, changed stays changed.
        case (_, nil): files[path] = kind
        }
        self.linesAdded += linesAdded
        self.linesRemoved += linesRemoved
    }

    /// "2 files added, 3 changed, 1 deleted · +120 −14 lines"
    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if modified > 0 { parts.append("\(modified) changed") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        guard !parts.isEmpty else { return "No file changes" }
        let total = files.count
        parts[0] = "\(total == 1 ? "1 file" : "\(total) files"): \(parts[0])"
        let lines = linesAdded + linesRemoved > 0 ? " · +\(linesAdded) −\(linesRemoved) lines" : ""
        return parts.joined(separator: ", ") + lines
    }

    private func count(_ kind: Kind) -> Int { files.values.filter { $0 == kind }.count }
}

/// Finds the files a shell command deletes (`rm`, `unlink`, `git rm`) as
/// absolute paths. Only literal paths count: globs and variables are skipped,
/// since there's no telling what they matched.
enum RemovalCommand {
    static func paths(in command: String, cwd: String) -> [String] {
        segments(of: command).flatMap { words -> [String] in
            var words = words[...]
            // `sudo rm …`, `FOO=1 rm …`
            while let first = words.first, first == "sudo" || first == "command" || isAssignment(first) {
                words.removeFirst()
            }
            guard let program = words.first.map({ ($0 as NSString).lastPathComponent }) else { return [] }
            let arguments: ArraySlice<String>
            switch program {
            case "rm", "unlink": arguments = words.dropFirst()
            case "git" where words.dropFirst().first == "rm": arguments = words.dropFirst(2)
            default: return []
            }
            var optionsEnded = false
            return arguments.compactMap { argument in
                if !optionsEnded, argument == "--" { optionsEnded = true; return nil }
                if !optionsEnded, argument.hasPrefix("-") { return nil }
                guard !argument.isEmpty, argument.rangeOfCharacter(from: unresolvable) == nil else { return nil }
                return resolve(argument, cwd: cwd)
            }
        }
    }

    private static let unresolvable = CharacterSet(charactersIn: "*?[{$`")

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func resolve(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
        return (absolute as NSString).standardizingPath
    }

    /// Splits on `;`, `&&`, `||`, `|`, `&` and newlines into simple commands,
    /// each a list of words with quotes and backslashes resolved.
    private static func segments(of command: String) -> [[String]] {
        var segments: [[String]] = []
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false

        func endWord() {
            if inWord { words.append(word) }
            word = ""
            inWord = false
        }
        func endSegment() {
            endWord()
            if !words.isEmpty { segments.append(words) }
            words = []
        }

        for character in command {
            if escaped {
                word.append(character)
                inWord = true
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\", open == "\"" {
                    escaped = true
                } else {
                    word.append(character)
                }
            } else if character == "\\" {
                escaped = true
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if ";|&\n".contains(character) {
                endSegment()
            } else if character.isWhitespace {
                endWord()
            } else {
                word.append(character)
                inWord = true
            }
        }
        endSegment()
        return segments
    }
}
