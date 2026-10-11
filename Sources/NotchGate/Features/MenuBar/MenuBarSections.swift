import SwiftUI

/// Install / remove the Claude Code hooks.
struct IntegrationSection: View {
    let installer: HookInstaller
    let editorHelper: EditorHelperInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                if installer.status == .installed {
                    Button("Remove", action: installer.uninstall)
                } else {
                    Button("Install hooks", action: installer.install)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Palette.clay)
                }
            }
            Text("Adds NotchGate to ~/.claude/settings.json (a backup is saved first). Restart running Claude sessions to pick it up.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !editorHelper.editors.isEmpty {
                EditorHelperRow(helper: editorHelper)
                    .padding(.top, 4)
            }
        }
    }

    private var statusText: String {
        switch installer.status {
        case .installed: return "Hooks installed"
        case .notInstalled: return "Hooks not installed"
        case .failed(let message): return message
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(helper.installed.isEmpty ? Color.secondary : Theme.Palette.success)
                    .frame(width: 7, height: 7)
                Text(title).font(.callout).lineLimit(1)
                Spacer()
                if helper.isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button(helper.installed.isEmpty ? "Install" : "Reinstall") {
                        Task { await helper.install() }
                    }
                }
            }
            SettingNote(detail)
        }
    }

    private var title: String {
        helper.installed.isEmpty
            ? "Editor helper not installed"
            : "Editor helper in \(helper.installed.sorted().joined(separator: ", "))"
    }

    private var detail: String {
        if let error = helper.lastError { return error }
        let windows = helper.connectedWindows
        if helper.installed.isEmpty {
            return "Lets the notch type prompts into Cursor / VS Code terminals."
        }
        return windows == 0
            ? "No editor window connected yet. Reload open windows once."
            : "\(windows) editor window\(windows == 1 ? "" : "s") connected. Prompts type straight into their terminals."
    }
}

extension IntegrationSection {
    var summary: String {
        installer.status == .installed ? "Hooks installed" : "Not connected"
    }
}

extension PermissionsSection {
    var summary: String {
        "Auto-allow \(settings.autoAllowPermissions ? "on" : "off")"
    }
}

extension NotchFeaturesSection {
    var summary: String {
        let switches = [settings.notchPermissions, settings.notchFileEdits, settings.questionMode != .terminal,
                        settings.notchPlans, settings.replyFromNotch]
        return "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}

/// Behavior toggles.
struct PreferencesSection: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingRow("Expand automatically", detail: "Open the full card as soon as Claude asks", isOn: $settings.autoExpand)
            SettingRow("Live activity on hover", detail: "Hover the notch to see every session", isOn: $settings.showActivityOnHover)
            SettingRow("Quick settings in the notch", isOn: $settings.showQuickSettingsInNotch, isIndented: true)
                .disabled(!settings.showActivityOnHover)
            SettingRow("Play a sound", isOn: $settings.playSound)
            SettingRow("“Claude finished” notices", detail: "A brief note in the notch when a task ends", isOn: $settings.showNotices)
            SettingRow("Check for updates", detail: "Looks for a newer NotchGate on GitHub", isOn: $settings.checkForUpdates)
            SettingRow("Launch at login", detail: "Opens the notch when you turn on your Mac", isOn: $launchAtLogin)
                .disabled(!LaunchAtLogin.isAvailable)
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.setEnabled(enabled) }
        }
    }
}

/// Auto-allow and question handling.
struct PermissionsSection: View {
    @Bindable var settings: AppSettings
    let onSetAutoAllow: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingRow(
                "Auto-allow permissions",
                detail: "Approve prompts instantly, with no card",
                isOn: Binding(get: { settings.autoAllowPermissions }, set: { [onSetAutoAllow] in onSetAutoAllow($0) })
            )
            SettingRow(
                "Still ask for risky commands",
                detail: "rm -rf, sudo, force push, DROP TABLE…",
                isOn: $settings.askForRiskyCommands,
                isIndented: true
            )
            .disabled(!settings.autoAllowPermissions)

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude's questions").font(.callout)
                Picker("Claude's questions", selection: $settings.questionMode) {
                    ForEach(QuestionMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                SettingNote(settings.questionMode.detail)
            }
            .padding(.top, 2)
        }
    }
}

/// Which request types NotchGate shows. Off = Claude Code handles it in the
/// terminal as if NotchGate weren't installed. Each row can preview its card.
struct NotchFeaturesSection: View {
    @Bindable var settings: AppSettings
    let onPreview: (DemoRequests.Sample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Permissions", detail: "Commands, web, MCP tools", sample: .permission, isOn: $settings.notchPermissions)
            row("File edits", detail: "Edit / Write approvals", sample: .edit, isOn: $settings.notchFileEdits)
            row("Questions", detail: "Claude asking you to choose", sample: .question, isOn: questionsBinding)
            row("Plan approvals", detail: "Approve before Claude codes", sample: .plan, isOn: $settings.notchPlans)
            row("Reply when done", detail: "Pop-up box to send the next prompt", sample: .completion, isOn: $settings.replyFromNotch)
            SettingNote("Off means the terminal handles it, just like without NotchGate.")
                .padding(.top, 2)
        }
    }

    /// On = answer in the notch (or "Don't ask"); off = terminal only.
    private var questionsBinding: Binding<Bool> {
        Binding(
            get: { settings.questionMode != .terminal },
            set: { settings.questionMode = $0 ? .notch : .terminal }
        )
    }

    private func row(_ title: String, detail: String, sample: DemoRequests.Sample, isOn: Binding<Bool>) -> some View {
        SettingRow(title: title, detail: detail, isOn: isOn) {
            Button { onPreview(sample) } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview this card")
        }
    }
}

/// Reference card for the global shortcuts.
struct ShortcutsSection: View {
    private let rows: [(String, String)] = [
        ("⌃⌥⏎", "Allow / approve"),
        ("⌃⌥⌫", "Deny / reject"),
        ("⌃⌥Space", "Expand or minimize"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingNote("These work anywhere while a request is waiting.")
            ForEach(rows, id: \.0) { keys, action in
                HStack {
                    Text(keys)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .frame(width: 64, alignment: .leading)
                    Text(action).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
