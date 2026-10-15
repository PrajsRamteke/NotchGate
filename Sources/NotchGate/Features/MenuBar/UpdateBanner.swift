import SwiftUI

/// Top-of-menu card shown when a newer NotchGate exists, while it installs,
/// or when an update attempt failed.
struct UpdateBanner: View {
    let updates: UpdateChecker

    var body: some View {
        switch updates.state {
        case .updating:
            card {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updating NotchGate…").font(.callout.weight(.semibold))
                        SettingNote("Downloading the new version. It restarts by itself.")
                    }
                }
                UpdateLogView()
                    .padding(.top, 8)
            }
        case .failed(let message):
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    UpdateLogView()
                    HStack {
                        Button("Try again") { Task { await retry() } }
                        Button("Show log", action: Updater.revealLog)
                            .disabled(!FileManager.default.fileExists(atPath: Updater.logURL.path))
                    }
                    .controlSize(.small)
                }
            }
        default:
            if let info = updates.available { availableCard(info) }
        }
    }

    private func availableCard(_ info: UpdateInfo) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.clay)
                    Spacer()
                    Button("Update") { Task { await updates.update() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Palette.clay)
                        .controlSize(.small)
                }
                Text(info.aheadBy == 1 ? "1 new change:" : "\(info.aheadBy) new changes:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(info.commits.prefix(4)) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.Palette.clay)
                        Text(commit.title).font(.caption).lineLimit(2)
                    }
                }
                if info.commits.count > 4 {
                    Text("and \(info.commits.count - 4) more").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func retry() async {
        if updates.isUpdateAvailable { await updates.update() } else { await updates.check() }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.clay.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Palette.clay.opacity(0.25), lineWidth: 0.5))
            .padding(.top, 10)
    }
}

/// Bottom-of-menu line: the installed version, what the last update check found,
/// and a refresh button to ask GitHub again right away.
struct UpdateStatusView: View {
    let updates: UpdateChecker

    var body: some View {
        HStack(spacing: 6) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: statusText)
            refreshButton
        }
    }

    /// Dev builds can't be compared with GitHub, and an install in progress shouldn't be interrupted.
    private var canRefresh: Bool {
        updates.state != .unsupported && updates.state != .updating
    }

    private var refreshHelp: String {
        switch updates.state {
        case .unsupported: return "Update checks are off for development builds"
        case .updating: return "Installing the update…"
        default: return "Check for updates"
        }
    }

    @ViewBuilder private var refreshButton: some View {
        if updates.state == .checking {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 14, height: 14)
        } else {
            Button {
                Task { await updates.check() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canRefresh)
            .opacity(canRefresh ? 1 : 0.4)
            .help(refreshHelp)
            .accessibilityLabel("Check for updates")
        }
    }

    private var statusText: String {
        switch updates.state {
        case .unsupported: return "\(versionText) · dev build"
        case .checking: return "\(versionText) · checking for updates…"
        case .upToDate: return "\(versionText) · up to date"
        default: return updates.isUpdateAvailable ? "\(versionText) · update available" : versionText
        }
    }

    private var versionText: String {
        // Dev builds (`swift run`) have no Info.plist; fall back to the release version.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.12.0"
        return updates.shortInstalledCommit.map { "v\(version) (\($0))" } ?? "v\(version)"
    }
}

/// The newest installer output (what `install.sh` prints), refreshed once a second while updating.
struct UpdateLogView: View {
    var lineCount = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(UpdateLog.recentLines(lineCount).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.25)))
        }
    }
}
