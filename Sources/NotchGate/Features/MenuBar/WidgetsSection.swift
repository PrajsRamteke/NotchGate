import SwiftUI

/// Glanceable widgets in the notch's hover panel. New widgets get a row here
/// and a switch in `AppSettings`.
struct WidgetsSection: View {
    @Bindable var settings: AppSettings
    let usage: UsageMonitor
    let session: SessionMonitor
    let resume: ResumeMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingRow(
                    "Usage",
                    info: "Your **5-hour** and **weekly** plan limits, and when they reset. Needs a Pro or Max plan.\n\nRead from Claude Code's status line; your own status line keeps working.",
                    isOn: Binding(get: { settings.usageWidget }, set: { [usage] in usage.setEnabled($0) })
                )
                if settings.usageWidget {
                    SettingStatus(usageStatus.text, tone: usageStatus.tone)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                GroupDivider()
                SettingRow(
                    "Session",
                    info: "Model, context used, cost and git branch for each running session, on its row in the notch.",
                    isOn: Binding(get: { settings.sessionWidget }, set: { [session] in session.setEnabled($0) })
                )
                if settings.sessionWidget {
                    SettingStatus(sessionStatus.text, tone: sessionStatus.tone)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                GroupDivider()
                SettingRow(
                    "Tool activity",
                    info: "How often each session calls Bash, Edit, Read and other tools, plus a heat strip of the last hour.",
                    isOn: $settings.toolsWidget
                )
                GroupDivider()
                SettingRow(
                    "Resume",
                    info: "Pick up a recent Claude Code session, or start a new one, in Terminal.\n\nRead from Claude Code's transcripts in **~/.claude/projects**.",
                    isOn: Binding(get: { settings.resumeWidget }, set: { [resume] in resume.setEnabled($0) })
                )
                if settings.resumeWidget, let resumeStatus {
                    SettingStatus(resumeStatus.text, tone: resumeStatus.tone)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if anyOn, !settings.showActivityOnHover {
                SettingStatus("Turn on Live activity on hover (Behavior) to see widgets.", tone: .warning)
                    .padding(.top, 9)
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.usageWidget)
        .animation(.snappy(duration: 0.25), value: settings.sessionWidget)
        .animation(.snappy(duration: 0.25), value: settings.resumeWidget)
    }

    private var anyOn: Bool { switches.contains(true) }

    private var switches: [Bool] {
        [settings.usageWidget, settings.sessionWidget, settings.toolsWidget, settings.resumeWidget]
    }

    private var resumeStatus: (text: String, tone: SettingStatus.Tone)? {
        if let error = resume.loadError { return (error, .error) }
        guard let latest = resume.recent.first else { return nil }
        return ("Last: \(latest.title) · \(latest.projectName)", .normal)
    }

    private var sessionStatus: (text: String, tone: SettingStatus.Tone) {
        if let error = session.setupError { return ("Couldn't connect to Claude Code: \(error)", .error) }
        guard let snapshot = session.latest else { return ("Waiting for Claude's next reply", .normal) }
        var parts: [String] = []
        if session.snapshots.count > 1 { parts.append("\(session.snapshots.count) sessions") }
        if let model = snapshot.model { parts.append(model) }
        if let percent = snapshot.contextPercent { parts.append("\(Int(percent.rounded()))% context") }
        if let cost = snapshot.costUSD { parts.append(SessionUsageDetails.costPhrase(cost)) }
        return (parts.isEmpty ? "Connected" : parts.joined(separator: " · "), .normal)
    }

    private var usageStatus: (text: String, tone: SettingStatus.Tone) {
        if let error = usage.setupError { return ("Couldn't connect to Claude Code: \(error)", .error) }
        guard let snapshot = usage.snapshot else { return ("Waiting for Claude's next reply", .normal) }
        let now = Date()
        let fiveHour = UsageGauge.fiveHour(snapshot, now: now)
        let weekly = UsageGauge.weekly(snapshot, now: now)
        let updated = UsageGauge.updatedPhrase(snapshot.updatedAt, now: now)
        return ("5h \(fiveHour.percent)% · week \(weekly.percent)% · \(updated.lowercased())", .normal)
    }
}

extension WidgetsSection {
    var summary: String {
        "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}
