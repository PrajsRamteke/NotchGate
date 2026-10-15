import SwiftUI

/// The menu-bar popover: status, Claude Code integration, preferences.
struct MenuBarContentView: View {
    let coordinator: AppCoordinator
    /// Overrides the screen-based cap on the scrolling middle (snapshots show it whole).
    var sectionsMaxHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            UpdateBanner(updates: coordinator.updates)
            Divider().padding(.vertical, 10)
            // Header and footer stay put; with every section open the middle scrolls instead of running off screen.
            CappedScroll(maxHeight: sectionsMaxHeight ?? screenSectionsMaxHeight, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    CollapsibleSection("Claude Code", symbol: "terminal", id: "claudeCode", summary: integration.summary) { integration }
                    CollapsibleSection("Show in notch", symbol: "bell.badge", id: "showInNotch", expandedByDefault: true, summary: features.summary) { features }
                    CollapsibleSection("Permissions & questions", symbol: "checkmark.shield", id: "permissions", summary: permissions.summary) { permissions }
                    CollapsibleSection("Widgets", symbol: "square.grid.2x2", id: "widgets", summary: widgets.summary) { widgets }
                    CollapsibleSection("Extras", symbol: "sparkles", id: "extras", summary: extras.summary) { extras }
                    CollapsibleSection("Behavior", symbol: "slider.horizontal.3", id: "behavior", summary: behavior.summary) { behavior }
                    CollapsibleSection("Shortcuts", symbol: "keyboard", id: "shortcuts", summary: "⌃⌥⏎ · ⌃⌥⌫") { ShortcutsSection() }
                }
                // Room inside the scroll view for the headers' hover fill.
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, -6)
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(16)
        .frame(width: 320)
        // Above the scroll area, so ⓘ bubbles aren't clipped by it.
        .infoTipHost()
        .onAppear {
            coordinator.installer.refresh()
            coordinator.editorHelper.refresh()
            coordinator.updates.checkOnMenuOpen()
        }
    }

    /// Room for the sections: the screen's usable height minus the header, a
    /// possible update banner and the footer, capped so the menu stays compact.
    private var screenSectionsMaxHeight: CGFloat {
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

    private var behavior: PreferencesSection {
        PreferencesSection(settings: coordinator.settings)
    }

    private var features: NotchFeaturesSection {
        NotchFeaturesSection(settings: coordinator.settings, onPreview: coordinator.preview)
    }

    private var permissions: PermissionsSection {
        PermissionsSection(settings: coordinator.settings, onSetAutoAllow: coordinator.island.setAutoAllow)
    }

    private var widgets: WidgetsSection {
        WidgetsSection(
            settings: coordinator.settings,
            usage: coordinator.island.usage,
            session: coordinator.island.session,
            resume: coordinator.island.resume
        )
    }

    private var extras: ExtrasSection {
        ExtrasSection(settings: coordinator.settings, water: coordinator.island.water, nowPlaying: coordinator.island.nowPlaying)
    }

    private var footer: some View {
        HStack {
            UpdateStatusView(updates: coordinator.updates)
            Spacer(minLength: 8)
            Button("Quit NotchGate") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .controlSize(.small)
        }
    }
}
