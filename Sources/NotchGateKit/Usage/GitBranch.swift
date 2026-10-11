import Foundation

/// The branch checked out in a directory, read straight from `.git/HEAD`.
///
/// The status line input doesn't carry the branch, and spawning `git` on every
/// status line update would slow the user's status line (and, without the
/// Command Line Tools, `/usr/bin/git` pops an install dialog instead).
public enum GitBranch {
    /// - Returns: the branch name, or `nil` outside a repository or on a detached HEAD.
    public static func current(in directory: String) -> String? {
        guard !directory.isEmpty else { return nil }
        let fileManager = FileManager.default
        var path = (directory as NSString).standardizingPath
        while true {
            let dotGit = (path as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                let gitDirectory = isDirectory.boolValue ? dotGit : linkedGitDirectory(dotGit, base: path)
                guard let gitDirectory else { return nil }
                return branch(fromHEAD: (gitDirectory as NSString).appendingPathComponent("HEAD"))
            }
            let parent = (path as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != path else { return nil }
            path = parent
        }
    }

    /// Worktrees and submodules have a `.git` file reading `gitdir: <path>`.
    private static func linkedGitDirectory(_ file: String, base: String) -> String? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return target.hasPrefix("/") ? target : (base as NSString).appendingPathComponent(target)
    }

    private static func branch(fromHEAD file: String) -> String? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        // Anything else is a detached HEAD: a bare commit hash.
        guard line.hasPrefix(prefix) else { return nil }
        let name = String(line.dropFirst(prefix.count))
        return name.isEmpty ? nil : name
    }
}
