import Foundation
import Testing
@testable import NotchGate

@Suite("Finding a session's editor window")
struct EditorWindowTests {
    private let storage = Data("""
    {
      "theme": "vs-dark",
      "windowsState": {
        "lastActiveWindow": { "folder": "file:///Users/me/Desktop/NotchGateProject/NotchGate", "backupPath": "/tmp/a" },
        "openedWindows": [
          { "folder": "file:///Users/me/Desktop/CRM-FE-BE/habuild-mobile" },
          { "folder": "file:///Users/me/Desktop/NotchGateProject/NotchGate" },
          { "folder": "file:///Users/me/Desktop/My%20Projects/auth-service" },
          { "folder": "vscode-remote://ssh-remote%2Bbox/home/me/api" },
          { "workspaceIdentifier": { "id": "abc", "configURIPath": "file:///Users/me/work/team.code-workspace" } }
        ]
      }
    }
    """.utf8)

    private func folder(_ path: String) -> EditorWindow.Workspace {
        EditorWindow.Workspace(target: URL(fileURLWithPath: path), folders: [path])
    }

    @Test func readsTheOpenWindowsOnceEach() {
        let workspaces = EditorWindow.workspaces(fromStorage: storage)
        let targets = workspaces.map(\.target.path)
        #expect(targets == [
            "/Users/me/Desktop/CRM-FE-BE/habuild-mobile",
            "/Users/me/Desktop/NotchGateProject/NotchGate",
            "/Users/me/Desktop/My Projects/auth-service",
            "/Users/me/work/team.code-workspace",
        ])
    }

    @Test func picksTheWindowHoldingTheSession() {
        let open = EditorWindow.workspaces(fromStorage: storage)
        let match = EditorWindow.workspace(containing: "/Users/me/Desktop/NotchGateProject/NotchGate/Sources", among: open)
        #expect(match?.target.path == "/Users/me/Desktop/NotchGateProject/NotchGate")
        #expect(EditorWindow.workspace(containing: "/Users/me/Desktop/My Projects/auth-service", among: open)?.target.lastPathComponent == "auth-service")
    }

    @Test func theClosestWorkspaceWinsAndLookalikesDont() {
        let open = [folder("/Users/me/code"), folder("/Users/me/code/app"), folder("/Users/me/code/app-old")]
        #expect(EditorWindow.workspace(containing: "/Users/me/code/app/src", among: open)?.target.path == "/Users/me/code/app")
        // "app-old" is not inside "app".
        #expect(EditorWindow.workspace(containing: "/Users/me/code/app-old", among: open)?.target.path == "/Users/me/code/app-old")
        #expect(EditorWindow.workspace(containing: "/Users/me/elsewhere", among: open) == nil)
    }

    @Test func aMultiRootWorkspaceMatchesThroughItsFolders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("team.code-workspace")
        // .code-workspace files allow comments and trailing commas.
        try Data("""
        {
          // shared setup
          "folders": [{ "path": "api" }, { "path": "/srv/web" },],
        }
        """.utf8).write(to: file)

        let storage = Data(#"{"windowsState":{"openedWindows":[{"workspaceIdentifier":{"configURIPath":"\#(file.absoluteString)"}}]}}"#.utf8)
        let open = EditorWindow.workspaces(fromStorage: storage)
        #expect(open.first?.folders == [directory.appendingPathComponent("api").standardizedFileURL.path, "/srv/web"])
        #expect(EditorWindow.workspace(containing: "/srv/web/src", among: open)?.target == file)
    }

    @Test func unreadableStorageMeansNoGuess() {
        #expect(EditorWindow.workspaces(fromStorage: Data("not json".utf8)).isEmpty)
        #expect(EditorWindow.workspaces(fromStorage: Data(#"{"theme":"dark"}"#.utf8)).isEmpty)
    }
}
