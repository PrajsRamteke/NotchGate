import AppKit
import Darwin

/// Brings the app hosting a Claude Code session (Terminal, iTerm, Ghostty,
/// VS Code, Cursor…) to the front by walking up the process tree from the
/// Claude process until it finds a regular GUI application.
enum TerminalActivator {
    private static let maxDepth = 24

    @MainActor
    @discardableResult
    static func activate(claudePID: Int32) -> Bool {
        var pid = claudePID
        for _ in 0..<maxDepth {
            guard pid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                return app.activate()
            }
            guard let parent = parentPID(of: pid), parent != pid else { break }
            pid = parent
        }
        return false
    }

    private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
