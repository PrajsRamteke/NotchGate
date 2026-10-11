import Foundation

/// Well-known filesystem locations shared by the app and the hook.
public enum BridgeLocation {
    /// Per-user support directory. Lives under `~/Library` (not `/tmp`) so the
    /// socket is only reachable by the current user.
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchGate", isDirectory: true)
    }

    /// Unix domain socket the app listens on.
    public static var socketURL: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCHGATE_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return supportDirectory.appendingPathComponent("bridge.sock")
    }

    /// Stable install location for the hook binary referenced from Claude settings.
    public static var installedHookURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchgate/bin/notchgate-hook")
    }
}
