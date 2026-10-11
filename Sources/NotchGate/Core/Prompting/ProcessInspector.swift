import Darwin
import Foundation

/// Read-only facts about a running process, gathered with `sysctl` (no
/// subprocesses, no special permissions: same-user processes only).
struct ProcessRecord: Equatable, Sendable {
    let pid: Int32
    let parentPID: Int32
    let name: String
    /// Controlling terminal, e.g. `/dev/ttys009`.
    let tty: String?
}

enum ProcessInspector {
    static func isAlive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno != ESRCH)
    }

    static func record(for pid: Int32) -> ProcessRecord? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }

        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let device = info.kp_eproc.e_tdev
        let tty = device == -1 ? nil : devname(device, S_IFCHR).map { "/dev/" + String(cString: $0) }
        return ProcessRecord(pid: pid, parentPID: info.kp_eproc.e_ppid, name: name, tty: tty)
    }

    /// The process and its ancestors, nearest first (stops before launchd).
    static func lineage(of pid: Int32, limit: Int = 32) -> [ProcessRecord] {
        var chain: [ProcessRecord] = []
        var current = pid
        while current > 1, chain.count < limit, let record = record(for: current) {
            chain.append(record)
            guard record.parentPID != current else { break }
            current = record.parentPID
        }
        return chain
    }

    /// Environment variables of a same-user process (`KERN_PROCARGS2`).
    static func environment(of pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// Parses the `KERN_PROCARGS2` layout:
    /// `argc (Int32) | exec path \0 | padding \0… | argv[0..<argc] \0 | env "K=V" \0 … \0`.
    static func parseProcArgs(_ bytes: [UInt8]) -> [String: String]? {
        guard bytes.count > 4 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = 4

        func skipString() { while index < bytes.count, bytes[index] != 0 { index += 1 } }
        func skipNulls() { while index < bytes.count, bytes[index] == 0 { index += 1 } }

        skipString()
        skipNulls()
        for _ in 0..<max(0, argc) {
            skipString()
            index += 1
        }

        var environment: [String: String] = [:]
        while index < bytes.count, bytes[index] != 0 {
            let start = index
            skipString()
            let entry = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            guard let separator = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return environment
    }
}
