import SwiftUI

/// Glanceable widgets in the notch's hover panel. New widgets get a row here
/// and a switch in `AppSettings`.
struct WidgetsSection: View {
    @Bindable var settings: AppSettings
    let usage: UsageMonitor
    let session: SessionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingRow(
                "Usage",
                detail: "5-hour and weekly limits, and when they reset",
                isOn: Binding(get: { settings.usageWidget }, set: { [usage] in usage.setEnabled($0) })
            )

            if settings.usageWidget {
                SettingNote(usageStatus)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingRow(
                "Session",
                detail: "Model, context used, cost and git branch",
                isOn: Binding(get: { settings.sessionWidget }, set: { [session] in session.setEnabled($0) })
            )

            if settings.sessionWidget {
                SettingNote(sessionStatus)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if anyOn, !settings.showActivityOnHover {
                SettingNote("Widgets show when you hover the notch. Turn on “Live activity on hover” under Behavior.")
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.usageWidget)
        .animation(.snappy(duration: 0.25), value: settings.sessionWidget)
    }

    private var anyOn: Bool { settings.usageWidget || settings.sessionWidget }

    private var sessionStatus: String {
        if let error = session.setupError { return "Couldn't connect to Claude Code: \(error)" }
        guard let snapshot = session.latest else {
            return "Waiting for Claude Code's next reply. Each session shows its own."
        }
        var parts: [String] = []
        if session.snapshots.count > 1 { parts.append("\(session.snapshots.count) sessions, latest:") }
        if let name = snapshot.projectName { parts.append(name) }
        if let model = snapshot.model { parts.append(model) }
        if let percent = snapshot.contextPercent { parts.append("\(Int(percent.rounded()))% context") }
        if let cost = snapshot.costUSD { parts.append(SessionUsageDetails.costPhrase(cost)) }
        if let branch = snapshot.branch { parts.append(branch) }
        return parts.joined(separator: " · ")
    }

    private var usageStatus: String {
        if let error = usage.setupError { return "Couldn't connect to Claude Code: \(error)" }
        let source = "Read from Claude Code's status line; yours still shows as before."
        guard let snapshot = usage.snapshot else {
            return "Waiting for Claude Code's next reply. Needs a Pro or Max plan. \(source)"
        }
        let now = Date()
        let fiveHour = UsageGauge.fiveHour(snapshot, now: now)
        let weekly = UsageGauge.weekly(snapshot, now: now)
        let updated = UsageGauge.updatedPhrase(snapshot.updatedAt, now: now)
        return "5h \(fiveHour.percent)% · week \(weekly.percent)% · \(updated.lowercased()). \(source)"
    }
}

extension WidgetsSection {
    var summary: String {
        let switches = [settings.usageWidget, settings.sessionWidget]
        return "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}
