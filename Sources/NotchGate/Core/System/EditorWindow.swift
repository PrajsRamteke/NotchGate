import AppKit

/// Brings forward the VS Code-family window (Cursor, VS Code, Windsurf,
/// VSCodium) whose workspace holds a session, with no extension and no extra
/// permission: asked to open a folder that's already open, the editor just
/// focuses that window, switching Space if needed.
///
/// The editor keeps the folders of its open windows in `storage.json`; the
/// session belongs to the one that contains its directory most closely.
enum EditorWindow {
    /// Each editor's folder under ~/Library/Application Support.
    static let supportFolders: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.exafunction.windsurf": "Windsurf",
        "com.vscodium": "VSCodium",
    ]

    /// An open window's workspace: one folder, or the folders of a .code-workspace file.
    struct Workspace: Equatable {
        /// What to open to focus the window.
        let target: URL
        let folders: [String]
    }

    /// `true` if the editor was asked to show the session's window.
    @MainActor
    static func focus(app: NSRunningApplication, showing cwd: String) -> Bool {
        guard let bundleID = app.bundleIdentifier, let appURL = app.bundleURL,
              let workspace = workspace(containing: cwd, among: openWorkspaces(bundleID: bundleID)) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([workspace.target], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    /// The open workspace closest around `cwd`: the deepest folder that contains it.
    static func workspace(containing cwd: String, among workspaces: [Workspace]) -> Workspace? {
        let session = standardized(cwd)
        var best: (workspace: Workspace, depth: Int)?
        for workspace in workspaces {
            for folder in workspace.folders.map(standardized) where session == folder || session.hasPrefix(folder + "/") {
                let depth = folder.split(separator: "/").count
                if depth > (best?.depth ?? -1) { best = (workspace, depth) }
            }
        }
        return best?.workspace
    }

    /// The workspaces of the editor's open windows, from its `storage.json`.
    static func openWorkspaces(bundleID: String) -> [Workspace] {
        guard let folder = supportFolders[bundleID] else { return [] }
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: storage) else { return [] }
        return workspaces(fromStorage: data)
    }

    /// Reads `windowsState` (open windows, plus the last active one).
    static func workspaces(fromStorage data: Data) -> [Workspace] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["windowsState"] as? [String: Any] else { return [] }
        var windows = state["openedWindows"] as? [[String: Any]] ?? []
        if let last = state["lastActiveWindow"] as? [String: Any] { windows.append(last) }
        var seen: Set<URL> = []
        return windows.compactMap(workspace(fromWindow:)).filter { seen.insert($0.target).inserted }
    }

    private static func workspace(fromWindow window: [String: Any]) -> Workspace? {
        if let folder = (window["folder"] as? String).flatMap(fileURL) {
            return Workspace(target: folder, folders: [folder.path])
        }
        // A multi-root workspace: focus it by opening its .code-workspace file.
        let identifier = window["workspaceIdentifier"] as? [String: Any] ?? window["workspace"] as? [String: Any]
        let config = (identifier?["configURIPath"] as? String ?? identifier?["configPath"] as? String).flatMap(fileURL)
        guard let config else { return nil }
        return Workspace(target: config, folders: folders(inWorkspaceFile: config))
    }

    /// The folders listed in a .code-workspace file, relative paths resolved against it.
    private static func folders(inWorkspaceFile url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
              let entries = root["folders"] as? [[String: Any]] else { return [] }
        let base = url.deletingLastPathComponent()
        return entries.compactMap { $0["path"] as? String }.map { path in
            path.hasPrefix("/") ? path : base.appendingPathComponent(path).standardizedFileURL.path
        }
    }

    /// Only local folders: a remote (SSH, container) window's URI isn't a path here.
    private static func fileURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }

    private static func standardized(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }
}
