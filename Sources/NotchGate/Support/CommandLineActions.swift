import AppKit
@preconcurrency import AVFoundation
import Foundation

/// Headless entry points so setup can be scripted:
///
///     NotchGate --setup                   hooks + editor helper + launch at login
///     NotchGate --uninstall               remove hooks + status line relay + disable launch at login
///     NotchGate --send-prompt PID TEXT    type a prompt into a Claude session (diagnostics)
///     NotchGate --focus-session PID DIR   bring a Claude session's own window/tab forward (diagnostics)
///     NotchGate --now-playing             print what the Now Playing helper reports for 5 s (diagnostics)
///     NotchGate --transcribe FILE [--live] run an audio file through Notch Voice's recognizer (diagnostics);
///                                         --live plays it at speaking pace and prints the live words too
///     NotchGate --snapshot DIR            render every card to PNG
@MainActor
enum CommandLineActions {
    /// Starts a requested action. Returns `true` if one was found; the action
    /// terminates the app itself when it's done.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if SnapshotRenderer.runIfRequested() { return finish(true) }
        if arguments.contains("--setup") { return runAsync(setUp) }
        if arguments.contains("--uninstall") { return finish(tearDown()) }
        if arguments.contains("--now-playing") { return runAsync(watchNowPlaying) }
        if let flag = arguments.firstIndex(of: "--transcribe"), arguments.count > flag + 1 {
            let path = arguments[flag + 1]
            let live = arguments.contains("--live")
            return runAsync { await transcribe(path, live: live) }
        }
        if let flag = arguments.firstIndex(of: "--focus-session"), arguments.count > flag + 2,
           let pid = Int32(arguments[flag + 1]) {
            let directory = arguments[flag + 2]
            return runAsync { await focusSession(pid, in: directory) }
        }
        if let flag = arguments.firstIndex(of: "--send-prompt"), arguments.count > flag + 2,
           let pid = Int32(arguments[flag + 1]) {
            let text = arguments[(flag + 2)...].joined(separator: " ")
            return runAsync { await sendPrompt(text, to: pid) }
        }
        return false
    }

    // MARK: Actions

    private static func setUp() async -> Bool {
        let installer = HookInstaller()
        installer.install()
        guard installer.status == .installed else {
            report("✗ Hook installation failed: \(installer.status)")
            return false
        }
        report("✓ Hooks installed → ~/.claude/settings.json (backup saved alongside)")
        for command in installer.conflictingCommands {
            report("⚠ Another PermissionRequest hook may race NotchGate: \(command)")
            report("  Remove it from ~/.claude/settings.json if prompts behave oddly.")
        }

        await installEditorHelper()

        guard LaunchAtLogin.isAvailable else {
            report("• Launch at login skipped (run from NotchGate.app to enable)")
            return true
        }
        LaunchAtLogin.setEnabled(true)
        report(LaunchAtLogin.isEnabled ? "✓ Launch at login enabled" : "• Launch at login needs approval in System Settings → Login Items")
        return true
    }

    /// Lets the notch type prompts into Cursor / VS Code terminals. Optional:
    /// failures are reported but never fail setup.
    private static func installEditorHelper() async {
        let helper = EditorHelperInstaller()
        guard !helper.editors.isEmpty else {
            report("• No VS Code-family editor found; skipped the editor helper")
            return
        }
        for (editor, succeeded) in await helper.install().sorted(by: { $0.key < $1.key }) {
            report(succeeded ? "✓ Editor helper installed in \(editor)" : "⚠ Editor helper failed in \(editor)")
        }
        if let error = helper.lastError { report("  \(error)") }
    }

    private static func tearDown() -> Bool {
        let installer = HookInstaller()
        installer.uninstall()
        // The status line widgets' relay: put the user's own status line back.
        let settings = AppSettings()
        UsageMonitor(settings: settings).setEnabled(false)
        SessionMonitor(settings: settings).setEnabled(false)
        LaunchAtLogin.setEnabled(false)
        report(installer.status == .notInstalled ? "✓ Hooks removed" : "✗ Removal failed: \(installer.status)")
        return installer.status == .notInstalled
    }

    /// Same code path as the notch's composer, for troubleshooting from a shell.
    private static func sendPrompt(_ text: String, to pid: Int32) async -> Bool {
        let host = TerminalHostDetector.detect(claudePID: pid)
        report("• Session \(pid) runs in: \(host.displayName)")
        do {
            let typed = try await PromptDispatcher().type(text, into: PromptTarget(sessionID: "", claudePID: pid, projectName: ""))
            report("✓ Typed into \(typed.displayName)")
            return true
        } catch {
            report("✗ \(error.localizedDescription)")
            return false
        }
    }

    /// Same path as the ↗ button on a session row.
    private static func focusSession(_ pid: Int32, in directory: String) async -> Bool {
        let host = TerminalHostDetector.detect(claudePID: pid)
        report("• Session \(pid) runs in: \(host.displayName)")
        TerminalActivator.activate(claudePID: pid, cwd: directory)
        try? await Task.sleep(for: .seconds(2))
        report("✓ Asked \(host.displayName) to show it")
        return true
    }

    /// Runs the real helper (without touching the user's settings) and prints each change.
    private static func watchNowPlaying() async -> Bool {
        let defaults = UserDefaults(suiteName: "now-playing-diagnostics") ?? .standard
        defaults.removePersistentDomain(forName: "now-playing-diagnostics")
        let monitor = NowPlayingMonitor(settings: AppSettings(defaults: defaults))
        monitor.setEnabled(true)
        if let error = monitor.setupError {
            report("✗ \(error)")
            return false
        }
        var last: String?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            let line = monitor.track.map { track in
                let position = track.position(at: Date()).map(NowPlayingTrack.clock) ?? "–"
                let duration = track.duration.map(NowPlayingTrack.clock) ?? "live"
                let artwork = monitor.artwork.map { "artwork \(Int($0.size.width))×\(Int($0.size.height))" } ?? "no artwork"
                return "\(track.isPlaying ? "▶" : "⏸") \(track.title) · \(track.subtitle ?? "–") · \(track.appName ?? "?") · \(position)/\(duration) · \(artwork) · shuffle \(track.shuffleMode.map(String.init) ?? "–") · repeat \(track.repeatMode.map(String.init) ?? "–") · commands \(track.commands.sorted())"
            } ?? "Nothing playing"
            if line != last { report(line) }
            last = line
        }
        monitor.stop()
        return monitor.setupError == nil
    }

    /// Streams an audio file through Notch Voice's recognizer in microphone-sized
    /// buffers, the same path a held shortcut takes (without the microphone or typing).
    private static func transcribe(_ path: String, live: Bool) async -> Bool {
        let provider = SpeechRecognizerProvider()
        let locale = VoiceLanguage.locale(for: AppSettings().voiceLanguage)
        do {
            let kind = try await provider.prepare(for: locale) { report("• Downloading the speech model… \(Int($0 * 100))%") }
            report("• Recognizer: \(kind), \(provider.locale?.identifier ?? locale.identifier)")
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            report("• Audio: \(Int(file.processingFormat.sampleRate)) Hz, \(file.processingFormat.channelCount) channel(s)")
            let started = Date()
            var onLiveText: (@Sendable (String) -> Void)?
            if live {
                // Called off the main actor: write straight to stdout.
                onLiveText = { text in
                    let line = String(format: "  %5.2f s  live: ", Date().timeIntervalSince(started)) + text + "\n"
                    FileHandle.standardOutput.write(Data(line.utf8))
                }
            }
            let session = try provider.makeSession(onLiveText: onLiveText)
            // 100 ms buffers; with --live, at the pace a microphone delivers them.
            let frames = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
                try file.read(into: buffer, frameCount: frames)
                if buffer.frameLength == 0 { break }
                session.append(buffer)
                if live { try await Task.sleep(for: .milliseconds(100)) }
            }
            let released = Date()
            let text = try await session.finish()
            report("✓ \(text.isEmpty ? "(nothing heard)" : text)")
            report("• Ready \(String(format: "%.2f", Date().timeIntervalSince(released))) s after the audio ended")
            return true
        } catch {
            report("✗ \((error as? VoiceError)?.detail ?? error.localizedDescription)")
            return false
        }
    }

    // MARK: Plumbing

    private static func runAsync(_ action: @escaping @MainActor () async -> Bool) -> Bool {
        Task { @MainActor in
            let succeeded = await action()
            exit(succeeded ? 0 : 1)
        }
        return true
    }

    private static func finish(_ succeeded: Bool) -> Bool {
        exit(succeeded ? 0 : 1)
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
