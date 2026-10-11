import SwiftUI

/// The Resume card: the last few Claude Code sessions that aren't running,
/// each a click from `claude --resume` in a new Terminal window, and a button
/// that starts a new session in a recent project (or any folder).
struct ResumeWidgetView: View {
    let monitor: ResumeMonitor
    /// Past sessions listed; fewer while sessions are running, so the panel stays short.
    var maxRows = ResumeMonitor.limit

    /// Where "New session" starts.
    enum Folder: Equatable {
        /// The most recent session's project.
        case latest
        case path(String)
        /// Terminal's default folder (home).
        case home
    }

    @State private var folder: Folder = .latest
    /// The folder list is open under the "New session" row.
    @State private var isPickingFolder = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .widgetCard()
        .animation(Theme.Motion.content, value: monitor.recent)
        .animation(Theme.Motion.content, value: monitor.launchError)
        .animation(Theme.Motion.content, value: monitor.loadError)
        .animation(Theme.Motion.content, value: isPickingFolder)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Resume", systemImage: "clock.arrow.circlepath")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                if monitor.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Palette.textTertiary)
                }
            }

            if let error = monitor.launchError ?? monitor.loadError {
                errorBanner(error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if monitor.recent.isEmpty {
                if !monitor.isLoading {
                    Text(monitor.loadError == nil ? "No earlier sessions to resume." : "Earlier sessions couldn't be listed.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(monitor.recent.prefix(maxRows).enumerated()), id: \.element.id) { index, session in
                        PastSessionRow(
                            session: session,
                            isLatest: index == 0,
                            now: now,
                            isLaunching: monitor.launching == session.id,
                            isBusy: monitor.launching != nil
                        ) { monitor.resume(session) }
                    }
                }
            }

            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 0.5)

            newSession

            if isPickingFolder {
                folderPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: New session

    private var newSession: some View {
        let launching = monitor.launching == ResumeMonitor.newSessionKey
        return HStack(alignment: .center, spacing: 8) {
            Button { monitor.startNew(in: targetDirectory) } label: {
                HStack(spacing: 6) {
                    if launching {
                        ProgressView().controlSize(.mini).tint(Theme.Palette.textPrimary)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text("New session")
                }
            }
            .buttonStyle(.island(.secondary))
            .disabled(monitor.launching != nil)
            .help("Opens Terminal and starts Claude Code in \(targetName)")

            Spacer(minLength: 0)

            Text("in")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            folderButton
        }
    }

    private var folderButton: some View {
        Button { isPickingFolder.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
                Text(targetName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isPickingFolder ? 180 : 0))
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(monitor.launching != nil)
        .help(targetDirectory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Your home folder")
    }

    /// The folder choices, listed inline beneath the row rather than in a pop-up menu.
    private var folderPanel: some View {
        let directories = monitor.recentDirectories
        return VStack(alignment: .leading, spacing: 0) {
            if !directories.isEmpty {
                Text("Recent projects")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            ForEach(directories, id: \.self) { path in
                FolderRow(title: URL(fileURLWithPath: path).lastPathComponent) {
                    folder = .path(path)
                    isPickingFolder = false
                }
            }
            FolderRow(title: "Home folder") {
                folder = .home
                isPickingFolder = false
            }
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            FolderRow(title: "Choose Folder…") {
                isPickingFolder = false
                monitor.chooseFolderAndStartNew()
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
        .disabled(monitor.launching != nil)
    }

    /// The folder "New session" uses; `nil` is Terminal's default (home).
    private var targetDirectory: String? {
        switch folder {
        case .latest: return monitor.defaultDirectory
        case .path(let path): return path
        case .home: return nil
        }
    }

    private var targetName: String {
        targetDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Home"
    }

    // MARK: Errors

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.Palette.warning)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            IconButton(systemName: "xmark", help: "Dismiss") { monitor.dismissError() }
                .padding(.vertical, -6)
                .padding(.trailing, -6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.warning.opacity(0.1)))
    }

    /// "just now", "12m ago", "3h ago", "2d ago", then the date.
    static func agePhrase(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes)m ago"
        case ..<(24 * 60): return "\(minutes / 60)h ago"
        case ..<(7 * 24 * 60): return "\(minutes / (24 * 60))d ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

/// One line in the folder list: full width, lit on hover.
private struct FolderRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovered ? Color.white.opacity(0.06) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// One past session: its title, project, branch and age, and a Resume button.
private struct PastSessionRow: View {
    let session: PastSession
    let isLatest: Bool
    let now: Date
    let isLaunching: Bool
    /// Another launch is underway.
    let isBusy: Bool
    let onResume: () -> Void

    @State private var isHovered = false

    var body: some View {
        // Checked as the row draws, so a folder deleted since the scan shows at once.
        let folderExists = ResumeMonitor.folderExists(session.directory)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(folderExists ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    Text(session.projectName)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let branch = session.branch {
                        Text("·")
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text("·")
                    Text(ResumeWidgetView.agePhrase(session.updatedAt, now: now))
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 6)
            if folderExists {
                resumeButton
            } else {
                Label("Folder missing", systemImage: "folder.badge.questionmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.Palette.warning)
                    .help("\((session.directory as NSString).abbreviatingWithTildeInPath) was moved or deleted, so this session can't be resumed.")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered && folderExists ? Color.white.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("\(session.title)\n\((session.directory as NSString).abbreviatingWithTildeInPath)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.projectName), \(ResumeWidgetView.agePhrase(session.updatedAt, now: now))")
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            HStack(spacing: 4) {
                if isLaunching {
                    ProgressView().controlSize(.mini).tint(Theme.Palette.ivory)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                Text("Resume")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isLatest ? Theme.Palette.ivory : Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(isLatest ? Theme.Palette.clay : Theme.Palette.surfaceRaised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy && !isLaunching ? 0.4 : 1)
        .help("Opens Terminal and runs claude --resume in \(session.projectName)")
        .accessibilityLabel("Resume \(session.title)")
    }
}
