import Foundation

/// The files `git status` lists in a project, with when each was last written.
///
/// The file tools (`Write`, `Edit`…) report what they changed, but a shell
/// command (`sed -i`, a `python` script, `git checkout`…) doesn't. Comparing a
/// snapshot taken before with one taken after finds what the shell touched.
struct WorkingTreeSnapshot: Equatable, Sendable {
    struct Stamp: Equatable, Sendable {
        let size: UInt64
        let modified: Date
    }

    struct Entry: Equatable, Sendable {
        /// Untracked, or newly added to the index.
        let isNew: Bool
        /// `nil` when the file isn't on disk (deleted).
        let stamp: Stamp?
    }

    /// Absolute path → state, for every file `git status` lists.
    private(set) var entries: [String: Entry]

    /// More changed files than this and the project isn't one to track
    /// (a build folder that isn't ignored, say).
    static let maxEntries = 5_000

    /// Files that differ between `baseline` and this snapshot: new or rewritten
    /// ones as added or changed, vanished ones as deleted.
    func changes(
        since baseline: WorkingTreeSnapshot,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [(path: String, kind: FileChanges.Kind)] {
        var result: [(path: String, kind: FileChanges.Kind)] = []
        for (path, entry) in entries.sorted(by: { $0.key < $1.key }) {
            let before = baseline.entries[path]
            if entry.stamp == nil {
                if before == nil || before?.stamp != nil { result.append((path, .deleted)) }
            } else if before?.stamp != entry.stamp {
                result.append((path, entry.isNew ? .added : .modified))
            }
        }
        // Gone from the list: reverted or committed (still on disk, nothing to
        // report), or an untracked file that was removed.
        for (path, before) in baseline.entries.sorted(by: { $0.key < $1.key })
        where entries[path] == nil && before.stamp != nil && !exists(path) {
            result.append((path, .deleted))
        }
        return result
    }

    // MARK: Reading git

    /// Reads `git status --porcelain=v1 -z` output. `nil` if it lists too many files.
    static func parse(
        status: String,
        root: String,
        stamp: (String) -> Stamp?
    ) -> WorkingTreeSnapshot? {
        var entries: [String: Entry] = [:]
        var fields = status.split(separator: "\0", omittingEmptySubsequences: true)[...]
        func absolute(_ relative: Substring) -> String {
            (root as NSString).appendingPathComponent(String(relative))
        }
        while let field = fields.popFirst() {
            guard field.count > 3 else { continue }
            let code = field.prefix(2)
            let path = absolute(field.dropFirst(3))
            if code.contains("R") || code.contains("C"), let original = fields.popFirst() {
                // A rename lists the new name first, then the old one, which is gone.
                if code.contains("R") { entries[absolute(original)] = Entry(isNew: false, stamp: stamp(absolute(original))) }
            }
            entries[path] = Entry(isNew: code == "??" || "ARC".contains(code.first ?? " "), stamp: stamp(path))
            if entries.count > maxEntries { return nil }
        }
        return WorkingTreeSnapshot(entries: entries)
    }

    /// Snapshot of the repository `cwd` is in; `nil` outside a git repository.
    static func capture(cwd: String) async -> WorkingTreeSnapshot? {
        guard let git = CommandRunner.locate("git", searchPath: nil),
              FileManager.default.fileExists(atPath: cwd),
              let top = try? await CommandRunner.run(git, ["-C", cwd, "rev-parse", "--show-toplevel"]), top.succeeded,
              // Reading must never take the index lock a commit may be waiting for.
              let status = try? await CommandRunner.run(
                  git,
                  ["-C", cwd, "-c", "core.quotepath=off", "status", "--porcelain=v1", "-z", "--untracked-files=all"],
                  environment: ["GIT_OPTIONAL_LOCKS": "0"],
                  timeout: 10
              ), status.succeeded
        else { return nil }
        let root = top.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return parse(status: status.stdout, root: root, stamp: stamp(ofFileAt:))
    }

    private static func stamp(ofFileAt path: String) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(size: size, modified: modified)
    }
}
