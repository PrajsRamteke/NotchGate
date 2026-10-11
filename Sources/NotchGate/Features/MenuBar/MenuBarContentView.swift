import SwiftUI

/// The menu-bar popover: status, Claude Code integration, preferences.
struct MenuBarContentView: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)
            IntegrationSection(installer: coordinator.installer)
            Divider().padding(.vertical, 10)
            PreferencesSection(settings: coordinator.settings)
            Divider().padding(.vertical, 10)
            PreviewSection(onPreview: coordinator.preview)
            Divider().padding(.vertical, 10)
            ShortcutsSection()
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { coordinator.installer.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ClaudeSpark(size: 22, isActive: coordinator.store.hasPending)
            VStack(alignment: .leading, spacing: 2) {
                Text("NotchGate")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(coordinator.serverError == nil ? Color.secondary : Theme.Palette.danger)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var statusLine: String {
        if let error = coordinator.serverError { return "Bridge offline — \(error)" }
        switch coordinator.store.pendingCount {
        case 0: return "Listening for Claude"
        case 1: return "1 request waiting"
        case let count: return "\(count) requests waiting"
        }
    }

    private var footer: some View {
        HStack {
            Text("v\(Bundle.main.shortVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit NotchGate") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
