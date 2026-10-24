import os

/// Namespaced unified-logging categories. View with:
/// `log stream --predicate 'subsystem == "app.notchgate"'`
enum Log {
    private static let subsystem = "app.notchgate"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let bridge = Logger(subsystem: subsystem, category: "bridge")
    static let hooks = Logger(subsystem: subsystem, category: "hooks")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let voice = Logger(subsystem: subsystem, category: "voice")
}
