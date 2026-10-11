import SwiftUI

/// Install / remove the Claude Code hooks.
struct IntegrationSection: View {
    let installer: HookInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Claude Code")
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

/// Behavior toggles.
struct PreferencesSection: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Behavior")
            Toggle("Expand automatically on new requests", isOn: $settings.autoExpand)
            Toggle("Show live activity when hovering the notch", isOn: $settings.showActivityOnHover)
            Toggle("Show quick settings in the notch", isOn: $settings.showQuickSettingsInNotch)
                .disabled(!settings.showActivityOnHover)
                .padding(.leading, 20)
            Toggle("Play a sound", isOn: $settings.playSound)
            Toggle("Show “Claude finished” notices", isOn: $settings.showNotices)
            Toggle("Pop up a reply box when Claude finishes", isOn: $settings.replyFromNotch)
            Text("Claude isn't paused. You can also reply anytime from the hover panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .disabled(!LaunchAtLogin.isAvailable)
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.setEnabled(enabled) }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// Auto-allow and question handling.
struct PermissionsSection: View {
    @Bindable var settings: AppSettings
    let onSetAutoAllow: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Permissions & questions")
            Toggle("Auto-allow permissions", isOn: Binding(get: { settings.autoAllowPermissions }, set: { [onSetAutoAllow] in onSetAutoAllow($0) }))
            Toggle("Still ask for risky commands (rm -rf, sudo, force push…)", isOn: $settings.askForRiskyCommands)
                .disabled(!settings.autoAllowPermissions)
                .padding(.leading, 20)
            Picker("Claude's questions", selection: $settings.questionMode) {
                ForEach(QuestionMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            Text(settings.questionMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// Which request types NotchGate shows. Off = Claude Code handles it in the
/// terminal as if NotchGate weren't installed. Each row can preview its card.
struct NotchFeaturesSection: View {
    @Bindable var settings: AppSettings
    let onPreview: (DemoRequests.Sample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Show in notch")
            row("Permissions", detail: "Commands, web, MCP tools", sample: .permission, isOn: $settings.notchPermissions)
            row("File edits", detail: "Edit / Write approvals", sample: .edit, isOn: $settings.notchFileEdits)
            row("Questions", detail: "Claude asking you to choose", sample: .question, isOn: questionsBinding)
            row("Plan approvals", detail: "Approve before Claude codes", sample: .plan, isOn: $settings.notchPlans)
            row("Reply when done", detail: "Pop-up box to send the next prompt", sample: .completion, isOn: $settings.replyFromNotch)
            Text("Off means the terminal handles it, just like without NotchGate.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { onPreview(sample) } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview this card")
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.Palette.clay)
        }
        .contentShape(Rectangle())
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
            SectionLabel("Shortcuts (while a request is waiting)")
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

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}
