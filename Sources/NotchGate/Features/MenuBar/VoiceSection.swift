import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Notch Voice settings: the switch, the permissions it needs, the hold-to-talk key,
/// the language, and the optional Claude clean-up.
struct VoiceSection: View {
    @Bindable var settings: AppSettings
    let voice: VoiceDictation

    var body: some View {
        SettingsGroup {
            SettingRow(
                title: "Notch Voice",
                info: "Hold your shortcut in any app, say what you want, and let go: your words are typed where the cursor is.\n\nApple's speech recognition runs on this Mac, so your audio never leaves it. Press ▶ to see where the pill appears.",
                isOn: Binding(get: { settings.voiceEnabled }, set: { [voice] in voice.setEnabled($0) })
            ) {
                PreviewButton(help: "Preview Notch Voice") { [voice] in voice.preview() }
            }

            if settings.voiceEnabled {
                VStack(alignment: .leading, spacing: 0) {
                    if !VoiceDictation.isUnbundled {
                        ForEach(voice.missingPermissions, id: \.self) { pane in
                            PermissionRow(pane: pane, permissions: voice.permissions) { [voice] in voice.request(pane) }
                        }
                    }
                    HStack(spacing: 8) {
                        SettingLabel(
                            title: "Hold to talk",
                            info: "The key, or two keys, you hold while speaking. Click, then press and release the keys you want; Esc keeps the current one.\n\nLeft and right count as different keys, so Right ⌥ leaves Left ⌥ free for shortcuts."
                        )
                        Spacer(minLength: 8)
                        ShortcutRecorderButton(voice: voice)
                    }
                    .settingRowPadding(isIndented: true)
                    HStack(spacing: 8) {
                        SettingLabel(
                            title: "Language",
                            info: "Pick the English that matches your accent: it's the biggest accuracy win. **Automatic** uses your Mac's region."
                        )
                        Spacer(minLength: 8)
                        Picker("Language", selection: Binding(get: { settings.voiceLanguage }, set: { [voice] in voice.setLanguage($0) })) {
                            ForEach(VoiceLanguage.options, id: \.id) { Text($0.title).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .settingRowPadding(isIndented: true)
                    SettingRow(
                        title: "AI clean-up",
                        info: "**On**: a model tidies your words before they're typed: punctuation, filler words, misheard code terms. Only the text is sent, never audio; if it fails or looks wrong, Apple's text is typed as is.\n\n**Off**: no AI. Your words appear live in the pill as you speak, and Apple's text is typed when you let go.",
                        isOn: Binding(get: { settings.voiceCleanupEnabled }, set: { [voice] in voice.setCleanupEnabled($0) }),
                        isIndented: true
                    ) {
                        EmptyView()
                    }
                    if settings.voiceCleanupEnabled {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                SettingLabel(
                                    title: "Model",
                                    info: "**OpenRouter (free)**: OpenRouter's free models, with your free OpenRouter key. 50 clean-ups a day (1,000 after a one-time $10 credit purchase). Free models' providers may keep or learn from the text.\n\n**Claude Haiku**: your Anthropic API key, billed to your account (a fraction of a cent each)."
                                )
                                Spacer(minLength: 8)
                                Picker("Model", selection: Binding(get: { settings.voiceCleanup }, set: { [voice] in voice.setCleanup($0) })) {
                                    ForEach(CleanupService.allCases) { Text($0.title).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .controlSize(.small)
                                .fixedSize()
                            }
                            .settingRowPadding(isIndented: true)
                            APIKeyRow(voice: voice, service: settings.voiceCleanup)
                                .id(settings.voiceCleanup)
                        }
                        .padding(.leading, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    statusRow
                    if let last = voice.lastTranscript {
                        LastTranscriptRow(text: last) { [voice] in voice.copyLastTranscript() }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.voiceEnabled)
        .animation(.snappy(duration: 0.25), value: settings.voiceCleanup)
        .animation(.snappy(duration: 0.25), value: settings.voiceCleanupEnabled)
        .animation(.snappy(duration: 0.25), value: voice.missingPermissions)
        .onAppear(perform: menuOpened)
        .background(WindowKeyObserver(onBecomeKey: menuOpened))
    }

    private func menuOpened() {
        voice.refreshPermissions()
        if settings.voiceEnabled, settings.voiceCleanupEnabled, settings.voiceCleanup == .openRouter { voice.refreshFreeAllowance() }
    }

    @ViewBuilder
    private var statusRow: some View {
        let status = self.status
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SettingStatus(status.text, tone: status.tone, isIndented: true)
            if case .failed(.modelDownloadFailed) = voice.readiness {
                Spacer(minLength: 4)
                Button("Try again") { voice.retryModel() }
                    .controlSize(.mini)
                    .padding(.bottom, 7)
            }
        }
        .padding(.top, 6)
    }

    private var status: (text: String, tone: SettingStatus.Tone) {
        switch voice.readiness {
        case .off:
            return ("", .normal)
        case .needsPermissions:
            return ("Allow the access above to start.", .warning)
        case .preparing(let progress):
            if let progress, progress > 0, progress < 1 {
                return ("Downloading Apple's speech model… \(Int(progress * 100))%", .normal)
            }
            return ("Getting the speech model ready…", .normal)
        case .failed(let error):
            return (error.detail, .error)
        case .ready:
            let cleanup = settings.voiceCleanup
            if settings.voiceCleanupEnabled, !voice.hasKey(for: cleanup) {
                return ("Add your \(cleanup.providerName) key to clean up; until then Apple's text is typed as is.", .warning)
            }
            if settings.voiceCleanupEnabled, let problem = voice.cleanupError {
                return (problem, .warning)
            }
            if settings.voiceShortcut.usesFunctionKeyAlone {
                return ("Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, or fn also opens its own menu.", .warning)
            }
            if voice.recognizerKind == .legacy {
                return ("Ready: hold \(settings.voiceShortcut.spokenName). macOS 26 or later recognizes speech more accurately.", .normal)
            }
            return ("Ready: hold \(settings.voiceShortcut.spokenName) in any app and speak.", .normal)
        }
    }
}

extension VoiceSection {
    var summary: String {
        settings.voiceEnabled ? "Hold \(settings.voiceShortcut.keycaps.joined(separator: " + "))" : "Off"
    }
}

// MARK: Permissions

private struct PermissionRow: View {
    let pane: VoicePermissions.Pane
    let permissions: VoicePermissions
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.warning)
            SettingLabel(title: title, info: info)
            Spacer(minLength: 8)
            Button(isFirstAsk ? "Allow" : "Open Settings", action: onAllow)
                .controlSize(.small)
        }
        .settingRowPadding(isIndented: true)
    }

    private var title: String {
        switch pane {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .speechRecognition: return "Speech Recognition"
        }
    }

    private var info: String {
        switch pane {
        case .microphone:
            return "So Notch Voice can hear you while you hold the key. Nothing is recorded otherwise."
        case .accessibility:
            return "So \(VoicePermissions.appName) can notice your shortcut in other apps and type the words where your cursor is.\n\n**Allow** adds it to System Settings' Accessibility list: switch it on there. If it's on but this still shows, macOS has forgotten it after an update: remove it with − and press **Allow** again."
        case .speechRecognition:
            return "macOS 14 and 15 need this for on-device speech recognition."
        }
    }

    private var isFirstAsk: Bool {
        switch pane {
        case .microphone: return permissions.microphone == .notAsked
        case .speechRecognition: return permissions.speechRecognition == .notAsked
        case .accessibility: return true
        }
    }
}

// MARK: Shortcut

/// Shows the shortcut as keycaps; click it, then press and release new keys.
private struct ShortcutRecorderButton: View {
    let voice: VoiceDictation
    @State private var recorder = ShortcutRecorder()
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button {
                if recorder.isRecording {
                    recorder.cancel()
                } else {
                    voice.isRecordingShortcut = true
                    recorder.begin { [voice] shortcut in
                        if let shortcut { voice.setShortcut(shortcut) }
                        voice.isRecordingShortcut = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    if recorder.isRecording, recorder.held.isEmpty {
                        Text("Press keys…")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.Palette.clay)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 18)
                    } else {
                        ForEach(keycaps, id: \.self) { MenuKeycap($0) }
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered || recorder.isRecording ? 0.06 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(recorder.isRecording ? Theme.Palette.clay : Color.primary.opacity(0.12), lineWidth: recorder.isRecording ? 1 : 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(recorder.isRecording ? "Press and release the keys, or Esc to keep the current one" : "Change the hold-to-talk key")
            .accessibilityLabel("Hold-to-talk key: \(voice.settings.voiceShortcut.spokenName)")

            if let message = recorder.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
        .animation(.snappy(duration: 0.2), value: recorder.isRecording)
    }

    private var keycaps: [String] {
        if recorder.isRecording, let live = VoiceShortcut(keys: recorder.held) { return live.keycaps }
        if recorder.isRecording { return recorder.held.sorted().map(\.keycap) }
        return voice.settings.voiceShortcut.keycaps
    }
}

/// Captures a new hold-to-talk shortcut: the modifier keys held together, saved when
/// they're all released. Only NotchGate's own window sees these keys.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    /// The keys down right now.
    private(set) var held: Set<ModifierKey> = []
    /// Why the last attempt didn't count.
    private(set) var message: String?

    @ObservationIgnored private var peak: Set<ModifierKey> = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((VoiceShortcut?) -> Void)?

    func begin(onFinish: @escaping (VoiceShortcut?) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        held = []
        peak = []
        message = nil
        self.onFinish = onFinish
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
        // The menu may close mid-recording; give up rather than wait forever.
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
    }

    func cancel() {
        finish(nil)
    }

    /// Returns whether to swallow the event: key presses never reach the menu while recording.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            if event.keyCode == UInt16(kVK_Escape) {
                finish(nil)
            } else {
                message = "Use modifier keys: ⌃ ⌥ ⇧ ⌘ or fn"
                peak = []
            }
            return true
        case .flagsChanged:
            held = ModifierKey.held(in: event.modifierFlags.rawValue)
            peak.formUnion(held)
            if held.isEmpty, !peak.isEmpty {
                if let shortcut = VoiceShortcut(keys: peak) {
                    finish(shortcut)
                } else {
                    message = "Use one or two keys"
                    peak = []
                }
            }
            return false
        default:
            return false
        }
    }

    private func finish(_ shortcut: VoiceShortcut?) {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timeout?.cancel()
        isRecording = false
        held = []
        if shortcut != nil { message = nil }
        let onFinish = self.onFinish
        self.onFinish = nil
        onFinish?(shortcut)
    }
}

// MARK: Claude clean-up

/// The API key for the chosen clean-up service: a field until one is saved, then its status.
private struct APIKeyRow: View {
    let voice: VoiceDictation
    let service: CleanupService
    @State private var draft = ""
    @State private var problem: String?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if voice.hasKey(for: service) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(savedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove") { voice.removeAPIKey(for: service) }
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    SecureField("\(service.providerName) API key", text: $draft, prompt: Text("\(service.keyPrefix)…"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(save)
                    Button(isChecking ? "Checking…" : "Save", action: save)
                        .controlSize(.small)
                        .disabled(draft.isEmpty || isChecking)
                }
                if let problem {
                    SettingStatus(problem, tone: .error)
                        .padding(.top, 3)
                } else {
                    let page = service.keyPage
                    let lead = service == .openRouter ? "Get a free key at" : "Create one in the"
                    // One wrapping line with an inline link.
                    Text(LocalizedStringKey("\(lead) [\(page.title)](\(page.url.absoluteString)) · text only, never audio"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .tint(Theme.Palette.clay)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 14)
        .padding(.bottom, 6)
    }

    private var savedText: String {
        guard service == .openRouter, let allowance = voice.freeAllowance else { return "Key saved in your keychain" }
        return "Key saved · \(allowance.remaining) of \(allowance.limit) free clean-ups left today"
    }

    private func save() {
        guard !draft.isEmpty, !isChecking else { return }
        isChecking = true
        problem = nil
        let key = draft
        Task {
            problem = await voice.saveAPIKey(key, for: service)
            isChecking = false
            if problem == nil { draft = "" }
        }
    }
}

private struct LastTranscriptRow: View {
    let text: String
    let onCopy: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Last: ").foregroundStyle(.tertiary) + Text(text).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Button {
                onCopy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copied ? Theme.Palette.success : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy the last dictation")
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, 14)
        .padding(.bottom, 7)
    }
}
