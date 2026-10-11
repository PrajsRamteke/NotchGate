import Foundation
import Observation

/// Installs the NotchGate Bridge extension into VS Code-family editors so the
/// notch can type prompts into their integrated terminals.
@MainActor
@Observable
final class EditorHelperInstaller {
    struct Editor: Identifiable, Equatable {
        let name: String
        let cli: String
        let extensionsDirectory: URL
        var id: String { name }
    }

    static let extensionID = "notchgate.notchgate-bridge"

    private(set) var editors: [Editor] = []
    private(set) var installed: Set<String> = []
    private(set) var isInstalling = false
    private(set) var lastError: String?

    /// Editor windows currently running the extension.
    var connectedWindows: Int { EditorBridgeTyper.connectedSockets.count }

    init() { refresh() }

    func refresh() {
        editors = Self.discoverEditors()
        installed = Set(editors.filter(Self.isInstalled).map(\.name))
    }

    /// Installs (or updates) the extension in every editor found.
    @discardableResult
    func install() async -> [String: Bool] {
        refresh()
        guard let vsix = Self.bundledVSIX else {
            lastError = "The editor helper package is missing from this build."
            return [:]
        }
        isInstalling = true
        lastError = nil
        defer { isInstalling = false; refresh() }

        var results: [String: Bool] = [:]
        for editor in editors {
            do {
                let output = try await CommandRunner.run(
                    editor.cli, ["--install-extension", vsix.path, "--force"], timeout: 120
                )
                results[editor.name] = output.succeeded
                if !output.succeeded { lastError = "\(editor.name): \(output.stderr.trimmed(or: "install failed"))" }
            } catch {
                results[editor.name] = false
                lastError = "\(editor.name): \(error.localizedDescription)"
            }
        }
        return results
    }

    // MARK: Discovery

    private static let knownEditors: [(name: String, app: String, cli: String, extensions: String)] = [
        ("Cursor", "Cursor.app", "cursor", ".cursor/extensions"),
        ("VS Code", "Visual Studio Code.app", "code", ".vscode/extensions"),
        ("VS Code Insiders", "Visual Studio Code - Insiders.app", "code-insiders", ".vscode-insiders/extensions"),
        ("Windsurf", "Windsurf.app", "windsurf", ".windsurf/extensions"),
        ("VSCodium", "VSCodium.app", "codium", ".vscode-oss/extensions"),
    ]

    private static func discoverEditors() -> [Editor] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        return knownEditors.compactMap { known in
            let cli = roots
                .map { $0.appendingPathComponent(known.app).appendingPathComponent("Contents/Resources/app/bin/\(known.cli)").path }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            return cli.map { Editor(name: known.name, cli: $0, extensionsDirectory: home.appendingPathComponent(known.extensions)) }
        }
    }

    private static func isInstalled(_ editor: Editor) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: editor.extensionsDirectory.path)) ?? []
        return entries.contains { $0.hasPrefix(extensionID + "-") }
    }

    /// Shipped in `NotchGate.app/Contents/Resources`, or next to a dev build.
    private static var bundledVSIX: URL? {
        let candidates = [
            Bundle.main.url(forResource: "notchgate-bridge", withExtension: "vsix"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("notchgate-bridge.vsix"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
