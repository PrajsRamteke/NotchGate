import SwiftUI

/// Install / remove the Claude Code hooks.
struct IntegrationSection: View {
    let installer: HookInstaller
    let editorHelper: EditorHelperInstaller

    var body: some View {
        SettingsGroup {
            HStack(spacing: 8) {
                StatusDot(color: statusColor)
                SettingLabel(
                    title: statusText,
                    info: "Connects NotchGate to Claude Code through hooks in **~/.claude/settings.json**. A backup is saved first.\n\nRestart running Claude sessions to pick it up."
                )
                Spacer(minLength: 8)
                if installer.status == .installed {
                    Button("Remove", action: installer.uninstall)
                        .controlSize(.small)
                } else {
                    Button("Install", action: installer.install)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Palette.clay)
                        .controlSize(.small)
                }
            }
            .settingRowPadding()
            if case .failed(let message) = installer.status {
                SettingStatus(message, tone: .error)
            }

            if !editorHelper.editors.isEmpty {
                GroupDivider()
                EditorHelperRow(helper: editorHelper)
            }
        }
    }

    private var statusText: String {
        switch installer.status {
        case .installed: return "Hooks installed"
        case .notInstalled: return "Hooks not installed"
        case .failed: return "Hooks couldn't install"
        }
    }

    private var statusColor: Color {
        switch installer.status {
        case .installed: return Theme.Palette.success
        case .notInstalled: return .secondary
        case .failed: return Theme.Palette.danger
        }
    }
}

/// Status of the Cursor / VS Code companion that lets the notch type prompts.
private struct EditorHelperRow: View {
    let helper: EditorHelperInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StatusDot(color: helper.installed.isEmpty ? .secondary : Theme.Palette.success)
                SettingLabel(
                    title: "Editor helper",
                    info: "Lets the notch type prompts straight into **Cursor** and **VS Code** terminals.\n\nAfter installing, reload open editor windows once."
                )
                Spacer(minLength: 8)
                if helper.isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button(helper.installed.isEmpty ? "Install" : "Reinstall") {
                        Task { await helper.install() }
                    }
                    .controlSize(.small)
                }
            }
            .settingRowPadding()
            if let status {
                SettingStatus(status.text, tone: status.tone)
            }
        }
    }

    private var status: (text: String, tone: SettingStatus.Tone)? {
        if let error = helper.lastError { return (error, .error) }
        guard !helper.installed.isEmpty else { return nil }
        let editors = helper.installed.sorted().joined(separator: ", ")
        let windows = helper.connectedWindows
        return windows == 0
            ? ("\(editors) · no window connected yet, reload once", .warning)
            : ("\(editors) · \(windows) window\(windows == 1 ? "" : "s") connected", .normal)
    }
}

/// Green / grey / red connection light before a status title.
private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

extension IntegrationSection {
    var summary: String {
        installer.status == .installed ? "Hooks installed" : "Not connected"
    }
}

extension PermissionsSection {
    var summary: String {
        settings.autoAllowPermissions ? "Auto-allow" : "Ask first"
    }
}

extension NotchFeaturesSection {
    var summary: String {
        let switches = [settings.notchPermissions, settings.notchFileEdits, settings.questionMode != .terminal,
                        settings.notchPlans, settings.replyFromNotch]
        return "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}

extension PreferencesSection {
    var summary: String {
        settings.autoExpand ? "Auto-expand on" : "Auto-expand off"
    }
}

/// Behavior toggles.
struct PreferencesSection: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        SettingsGroup {
            SettingRow(
                "Expand automatically",
                info: "Opens the full card the moment Claude asks for something, instead of a small alert you click to open.",
                isOn: $settings.autoExpand
            )
            GroupDivider()
            SettingRow(
                "Live activity on hover",
                info: "Hover the notch to see every running Claude session, its progress, and your widgets.",
                isOn: $settings.showActivityOnHover
            )
            SettingRow(
                "Quick settings",
                info: "Puts the auto-allow switch and question mode at the bottom of the hover panel.\n\nNeeds **Live activity on hover**.",
                isOn: $settings.showQuickSettingsInNotch,
                isIndented: true,
                isDisabled: !settings.showActivityOnHover
            )
            SettingRow(
                "Live badge while closed",
                info: "While a Claude session is working, a moving waveform sits on the right of the closed notch, so you know it's still running.",
                isOn: $settings.liveInClosedNotch
            )
            GroupDivider()
            SettingRow(
                "Sounds",
                info: "Short sounds when Claude needs you or finishes, and the water reminder's.\n\nTurn off for silence.",
                isOn: $settings.playSound
            )
            if settings.playSound {
                VStack(alignment: .leading, spacing: 0) {
                    SoundPickerRow(
                        title: "Claude needs you",
                        info: "A card or an alert arrives: a permission, a question, a plan, or anything else Claude is waiting on.",
                        selection: $settings.attentionSound,
                        volume: SoundPlayer.attentionVolume
                    )
                    SoundPickerRow(
                        title: "Claude finished",
                        info: "Plays with the reply box (**Reply when done**) or the **“Finished” notice**. With both off, Claude finishes quietly.",
                        selection: $settings.finishedSound,
                        volume: SoundPlayer.finishedVolume
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            GroupDivider()
            SettingRow(
                "“Finished” notices",
                info: "Shows a brief note in the notch when Claude finishes a task.",
                isOn: $settings.showNotices
            )
            GroupDivider()
            SettingRow(
                "Check in the background",
                info: "Checks GitHub every few hours, even with this menu closed, and puts a dot on the menu bar icon when an update is out.\n\nOpening this menu always checks.",
                isOn: $settings.checkForUpdates
            )
            GroupDivider()
            SettingRow(
                "Launch at login",
                info: "Starts NotchGate when you log in to your Mac.",
                isOn: $launchAtLogin,
                isDisabled: !LaunchAtLogin.isAvailable
            )
            .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.setEnabled(enabled) }
        }
        .animation(.snappy(duration: 0.25), value: settings.playSound)
    }
}

/// Picks the sound for one cue. Choosing a sound plays it, and ▶ plays it again.
private struct SoundPickerRow: View {
    let title: String
    let info: String
    @Binding var selection: AlertSound
    let volume: Float

    var body: some View {
        HStack(spacing: 8) {
            SettingLabel(title: title, info: info)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                Text(AlertSound.none.rawValue).tag(AlertSound.none)
                Divider()
                ForEach(AlertSound.sounds) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            PreviewButton(help: "Listen") { SoundPlayer.preview(selection, volume: volume) }
                .disabled(selection == .none)
                .opacity(selection == .none ? 0.4 : 1)
        }
        .settingRowPadding(isIndented: true)
        .onChange(of: selection) { _, sound in SoundPlayer.preview(sound, volume: volume) }
    }
}

/// Auto-allow and question handling.
struct PermissionsSection: View {
    @Bindable var settings: AppSettings
    let onSetAutoAllow: @MainActor (Bool) -> Void

    var body: some View {
        SettingsGroup {
            SettingRow(
                "Auto-allow permissions",
                info: "Approves Claude's permission prompts instantly, with no card to click.",
                isOn: Binding(get: { settings.autoAllowPermissions }, set: { [onSetAutoAllow] in onSetAutoAllow($0) })
            )
            SettingRow(
                "Still ask for risky ones",
                info: "Even with auto-allow on, dangerous commands still stop and ask: **rm -rf**, **sudo**, **git push --force**, **DROP TABLE** and similar.",
                isOn: $settings.askForRiskyCommands,
                isIndented: true,
                isDisabled: !settings.autoAllowPermissions
            )
            GroupDivider()
            VStack(alignment: .leading, spacing: 8) {
                SettingLabel(title: "Claude's questions", info: QuestionMode.explanation)
                Picker("Claude's questions", selection: $settings.questionMode) {
                    ForEach(QuestionMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .settingRowPadding()
            .padding(.bottom, 2)
        }
    }
}

/// Which request types NotchGate shows. Off = answered in the terminal, with
/// only an alert in the notch. Each row can preview its card.
struct NotchFeaturesSection: View {
    @Bindable var settings: AppSettings
    let onPreview: (DemoRequests.Sample) -> Void

    private static let offNote = "\n\nWhen off, you answer in the terminal and the notch only alerts you."

    var body: some View {
        SettingsGroup {
            row("Permissions", info: "Approve commands, web fetches and MCP tools from the notch." + Self.offNote,
                sample: .permission, isOn: $settings.notchPermissions)
            GroupDivider()
            row("File edits", info: "Review Edit and Write changes as a diff in the notch before they're applied." + Self.offNote,
                sample: .edit, isOn: $settings.notchFileEdits)
            GroupDivider()
            row("Questions", info: "Answer Claude's multiple-choice questions from the notch." + Self.offNote,
                sample: .question, isOn: questionsBinding)
            GroupDivider()
            row("Plan approvals", info: "Read and approve Claude's plan in the notch before it starts coding." + Self.offNote,
                sample: .plan, isOn: $settings.notchPlans)
            GroupDivider()
            row("Reply when done", info: "When Claude finishes, a reply box pops up so you can send the next prompt without switching windows.",
                sample: .completion, isOn: $settings.replyFromNotch)
        }
    }

    /// On = answer in the notch (or "Don't ask"); off = terminal only.
    private var questionsBinding: Binding<Bool> {
        Binding(
            get: { settings.questionMode != .terminal },
            set: { settings.questionMode = $0 ? .notch : .terminal }
        )
    }

    private func row(_ title: String, info: String, sample: DemoRequests.Sample, isOn: Binding<Bool>) -> some View {
        SettingRow(title: title, info: info, isOn: isOn) {
            PreviewButton { onPreview(sample) }
        }
    }
}

/// Shows a demo in the notch.
struct PreviewButton: View {
    var help = "Preview this card"
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isHovered ? Theme.Palette.clay : Color.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Reference card for the global shortcuts.
struct ShortcutsSection: View {
    private let rows: [(keys: [String], action: String)] = [
        (["⌃", "⌥", "⏎"], "Allow / approve"),
        (["⌃", "⌥", "⌫"], "Deny / reject"),
        (["⌃", "⌥", "Space"], "Expand or minimize"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { GroupDivider() }
                    HStack {
                        Text(row.action).font(.callout)
                        Spacer(minLength: 8)
                        HStack(spacing: 3) {
                            ForEach(row.keys, id: \.self) { MenuKeycap($0) }
                        }
                    }
                    .settingRowPadding()
                }
            }
            SettingStatus("Work anywhere while a request is waiting.")
                .padding(.top, 9)
        }
    }
}

/// A keycap in the system-themed menu (the island's `KeyHint` is dark-only).
struct MenuKeycap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
