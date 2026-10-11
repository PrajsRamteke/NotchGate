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

    /// Latest plan usage, written by the hook's status line relay (see `UsageSnapshot`).
    public static var usageURL: URL {
        supportDirectory.appendingPathComponent("usage.json")
    }

    /// The latest session's model, context, cost and branch (see `SessionSnapshot`).
    public static var sessionURL: URL {
        supportDirectory.appendingPathComponent("session.json")
    }

    /// The user's own `statusLine` setting, kept while NotchGate's relay sits
    /// in its place. The relay runs its command; removing the relay restores it.
    public static var originalStatusLineURL: URL {
        supportDirectory.appendingPathComponent("statusline-original.json")
    }

    /// Stable install location for the hook binary referenced from Claude settings.
    public static var installedHookURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notchgate/bin/notchgate-hook")
    }
}
