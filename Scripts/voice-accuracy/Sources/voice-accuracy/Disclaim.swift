import Darwin
import Foundation

/// macOS asks the *responsible* process for privacy permissions, which for a command-line
/// tool is the terminal app. Terminal.app declares no microphone or speech usage text, so
/// requests crash. Relaunching ourselves as our own responsible process makes macOS use
/// the usage descriptions embedded in this binary instead (see Package.swift).
enum Disclaim {
    private static let marker = "VOICE_ACCURACY_DISCLAIMED"

    private typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

    /// Re-executes this binary as its own responsible process and exits with its status.
    /// Returns without doing anything when already relaunched, or when the call is missing.
    static func relaunchIfNeeded() {
        guard ProcessInfo.processInfo.environment[marker] == nil,
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") // RTLD_DEFAULT
        else { return }
        let setDisclaim = unsafeBitCast(symbol, to: SetDisclaim.self)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        guard setDisclaim(&attributes, 1) == 0 else { return }

        setenv(marker, "1", 1)
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        guard posix_spawn(&pid, path, nil, &attributes, &argv, environ) == 0 else {
            unsetenv(marker)
            return
        }
        // The child owns the terminal now; let it handle Ctrl-C.
        signal(SIGINT, SIG_IGN)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let exited = status & 0x7f == 0
        exit(exited ? (status >> 8) & 0xff : 128 + (status & 0x7f))
    }
}
