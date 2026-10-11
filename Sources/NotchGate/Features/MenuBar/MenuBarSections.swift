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
            Toggle("Play a sound", isOn: $settings.playSound)
            Toggle("Show “Claude finished” notices", isOn: $settings.showNotices)
            Toggle("Reply from the notch when Claude stops", isOn: $settings.holdForReplyOnStop)
            if settings.holdForReplyOnStop {
                Text("Not a permission — Claude waits up to the time below for your reply, then continues in the terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
            if settings.holdForReplyOnStop {
                Stepper(value: $settings.replyWindowSeconds, in: 15...300, step: 15) {
                    Text("Wait \(settings.replyWindowSeconds)s for a reply")
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .disabled(!LaunchAtLogin.isAvailable)
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.setEnabled(enabled) }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// Fire sample requests to see the island without a live Claude session.
struct PreviewSection: View {
    let onPreview: (DemoRequests.Sample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Preview")
            HStack(spacing: 6) {
                ForEach(DemoRequests.Sample.allCases) { sample in
                    Button(sample.rawValue) { onPreview(sample) }
                        .controlSize(.small)
                }
            }
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
