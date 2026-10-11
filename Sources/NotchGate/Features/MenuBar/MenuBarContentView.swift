import SwiftUI

/// The menu-bar popover: status, Claude Code integration, preferences.
struct MenuBarContentView: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            UpdateBanner(updates: coordinator.updates)
            Divider().padding(.vertical, 10)
            // Header and footer stay put; with every section open the middle scrolls instead of running off screen.
            CappedScroll(maxHeight: sectionsMaxHeight, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    CollapsibleSection("Claude Code", id: "claudeCode", summary: integration.summary) { integration }
                    Divider().padding(.vertical, 10)
                    CollapsibleSection("Show in notch", id: "showInNotch", expandedByDefault: true, summary: features.summary) { features }
                    Divider().padding(.vertical, 10)
                    CollapsibleSection("Permissions & questions", id: "permissions", summary: permissions.summary) { permissions }
                    Divider().padding(.vertical, 10)
                    CollapsibleSection("Extras", id: "extras", summary: extras.summary) { extras }
                    Divider().padding(.vertical, 10)
                    CollapsibleSection("Behavior", id: "behavior") { PreferencesSection(settings: coordinator.settings) }
                    Divider().padding(.vertical, 10)
                    CollapsibleSection("Shortcuts", id: "shortcuts", summary: "⌃⌥⏎ · ⌃⌥⌫ · ⌃⌥Space") { ShortcutsSection() }
                }
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            coordinator.installer.refresh()
            coordinator.editorHelper.refresh()
        }
    }

    /// Room for the sections: the screen's usable height minus the header, a
    /// possible update banner and the footer, capped so the menu stays compact.
    private var sectionsMaxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(560, max(240, screenHeight - 320))
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

    private var integration: IntegrationSection {
        IntegrationSection(installer: coordinator.installer, editorHelper: coordinator.editorHelper)
    }

    private var features: NotchFeaturesSection {
        NotchFeaturesSection(settings: coordinator.settings, onPreview: coordinator.preview)
    }

    private var permissions: PermissionsSection {
        PermissionsSection(settings: coordinator.settings, onSetAutoAllow: coordinator.island.setAutoAllow)
    }

    private var extras: ExtrasSection {
        ExtrasSection(settings: coordinator.settings, water: coordinator.island.water)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            UpdateStatusView(updates: coordinator.updates)
            HStack {
                Spacer()
                Button("Quit NotchGate") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

