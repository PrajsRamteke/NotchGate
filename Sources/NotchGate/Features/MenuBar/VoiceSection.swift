import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Notch Voice settings: the switch, the permissions it needs, the hold-to-talk key,
/// the speech model and its language.
struct VoiceSection: View {
    @Bindable var settings: AppSettings
    let voice: VoiceDictation

    var body: some View {
        SettingsGroup {
            SettingRow(
                title: "Notch Voice",
                info: "Hold your shortcut in any app, say what you want, and let go: your words are typed where the cursor is.\n\nSpeech is recognized on this Mac, by Apple's recognizer or a free open-source model you download, so your audio never leaves it. Press ▶ to see where the pill appears.",
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
                    SpeechModelList(voice: voice)
                    languageRow
                    statusRow
                    if let last = voice.lastTranscript {
                        LastTranscriptRow(text: last) { [voice] in voice.copyLastTranscript() }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.voiceEnabled)
        .animation(.snappy(duration: 0.25), value: voice.missingPermissions)
        .animation(.snappy(duration: 0.25), value: voice.speechModel)
        .onAppear(perform: menuOpened)
        .background(WindowKeyObserver(onBecomeKey: menuOpened))
    }

    private func menuOpened() {
        voice.refreshPermissions()
        voice.refreshModels()
    }

    /// The active model's languages, when it offers a choice.
    @ViewBuilder
    private var languageRow: some View {
        let model = voice.speechModel
        if !model.languages.isEmpty {
            HStack(spacing: 8) {
                SettingLabel(
                    title: "Language",
                    info: model.engine == .apple
                        ? "Pick the English that matches your accent: it's the biggest accuracy win. **Automatic** uses your Mac's region."
                        : "\(model.name) works out the language by itself. Pick one if it guesses wrong."
                )
                Spacer(minLength: 8)
                Picker("Language", selection: Binding(get: { voice.language(for: model) }, set: { [voice] in voice.setLanguage($0, for: model) })) {
                    ForEach(model.languages, id: \.id) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .settingRowPadding(isIndented: true)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let status = self.status
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SettingStatus(status.text, tone: status.tone, isIndented: true)
            if case .failed(let error) = voice.readiness, error.canRetry {
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
            if let next = voice.switchingTo {
                if next.engine == .bark, !BarkTranscriber.isOptimized(in: voice.models.folder(for: next)) {
                    return ("Optimizing \(next.name) for this Mac's Neural Engine: a few minutes, just once. \(voice.typingModelName) types until then.", .normal)
                }
                return ("Loading \(next.name)… \(voice.typingModelName) types until then.", .normal)
            }
            if settings.voiceShortcut.usesFunctionKeyAlone {
                return ("Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing, or fn also opens its own menu.", .warning)
            }
            if voice.recognizerKind == .legacy {
                return ("Ready: hold \(settings.voiceShortcut.spokenName). macOS 26 or later recognizes speech more accurately.", .normal)
            }
            if voice.speechModel.engine != .apple {
                return ("Ready: hold \(settings.voiceShortcut.spokenName) in any app and speak. \(voice.speechModel.name) types what it hears.", .normal)
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

// MARK: Speech models

/// Every speech model, one row each: pick a downloaded one to type with, or download one.
private struct SpeechModelList: View {
    let voice: VoiceDictation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingLabel(
                title: "Speech model",
                info: "Which model turns your speech into text. Every one runs on this Mac, with no account or API key, and your audio never leaves it.\n\n**Apple** is built in. The others are free, open-source models: download one once and its own text is typed, with no Apple step."
            )
            .padding(.bottom, 2)
            ForEach(SpeechModel.catalog) { model in
                SpeechModelRow(voice: voice, model: model)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 14)
    }
}

struct SpeechModelRow: View {
    let voice: VoiceDictation
    let model: SpeechModel
    @State private var confirmingRemoval = false
    @State private var isHovered = false
    /// Who the model suits, in a bubble once the pointer rests on the row.
    @State private var showsWhy = false
    @State private var pendingWhy: Task<Void, Never>?
    @Environment(\.infoTipPreview) private var preview

    private var state: SpeechModelStore.State { voice.models.state(of: model) }
    private var isActive: Bool { voice.speechModel == model }
    private var canSelect: Bool { state == .downloaded && model.unsupportedReason == nil && !isActive }

    var body: some View {
        HStack(spacing: 8) {
            radio
            VStack(alignment: .leading, spacing: 1) {
                SettingLabel(title: model.name, info: model.about)
                Text(subtitle.text)
                    .font(.caption)
                    .foregroundStyle(subtitle.isProblem ? AnyShapeStyle(Theme.Palette.danger) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(model.unsupportedReason == nil ? 1 : 0.55)
            // The words take the width they need before the gap does.
            .layoutPriority(1)
            Spacer(minLength: 6)
            accessory
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.06 : isHovered && canSelect ? 0.035 : 0))
        )
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .onTapGesture { if canSelect { voice.selectModel(model) } }
        .onDisappear { pendingWhy?.cancel() }
        .infoTip(model.whyPick, isShowing: showsWhy || preview == Self.whyPreview(model))
        .accessibilityHint(Text(InfoTip.attributed(model.whyPick)))
        .animation(.snappy(duration: 0.2), value: state)
    }

    /// Snapshots: shows this row's bubble open.
    static func whyPreview(_ model: SpeechModel) -> String {
        "why \(model.id)"
    }

    /// A longer pause than an ⓘ's, so moving down the list doesn't flash every bubble.
    private func hover(_ hovering: Bool) {
        isHovered = hovering
        pendingWhy?.cancel()
        guard hovering else {
            showsWhy = false
            return
        }
        pendingWhy = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            showsWhy = true
        }
    }

    @ViewBuilder
    private var radio: some View {
        if voice.switchingTo == model {
            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        } else {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? AnyShapeStyle(Theme.Palette.clay) : AnyShapeStyle(.tertiary))
                .frame(width: 14, height: 14)
                .opacity(state == .downloaded ? 1 : 0.45)
        }
    }

    private var subtitle: (text: String, isProblem: Bool) {
        if let reason = model.unsupportedReason { return (reason, false) }
        if case .failed(let reason) = state { return (reason, true) }
        return ("\(model.summary) · \(model.languageSummary)", false)
    }

    @ViewBuilder
    private var accessory: some View {
        if model.unsupportedReason != nil {
            EmptyView()
        } else {
            switch state {
            case .notDownloaded:
                Button { voice.download(model) } label: {
                    Label(Self.megabytes(model.downloadSize), systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .help("Download \(model.name) from Hugging Face")
            case .downloading(let progress):
                HStack(spacing: 5) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.Palette.clay)
                        .frame(width: 46)
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    Button { voice.cancelDownload(model) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop downloading")
                }
            case .failed:
                Button("Try again") { voice.download(model) }
                    .controlSize(.small)
            case .downloaded where model.isBuiltIn:
                EmptyView()
            case .downloaded:
                removeButton
            }
        }
    }

    /// Two clicks, so one stray click doesn't throw away a download.
    @ViewBuilder
    private var removeButton: some View {
        if confirmingRemoval {
            Button("Remove") {
                confirmingRemoval = false
                voice.removeModel(model)
            }
            .controlSize(.small)
            .tint(Theme.Palette.danger)
            .task {
                try? await Task.sleep(for: .seconds(3))
                confirmingRemoval = false
            }
        } else {
            Button { confirmingRemoval = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 1 : 0.55)
            .help("Remove \(model.name) from this Mac (\(Self.megabytes(model.downloadSize)))")
        }
    }

    static func megabytes(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
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
