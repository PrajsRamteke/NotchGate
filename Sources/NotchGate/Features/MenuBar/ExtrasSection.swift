import SwiftUI

/// Optional notch features that have nothing to do with Claude. New extras
/// get a row here and a switch in `AppSettings`.
struct ExtrasSection: View {
    @Bindable var settings: AppSettings
    let water: WaterReminder
    let nowPlaying: NowPlayingMonitor

    static let intervals = 5...240
    static let snoozeOptions = [5, 10, 15, 30]

    var body: some View {
        SettingsGroup {
            SettingRow(
                "Water reminder",
                info: "A little bot, Spidey or Batman drops from the notch with a bottle to remind you to drink.\n\nThe timer waits while you're away from your Mac.",
                isOn: Binding(get: { settings.waterReminder }, set: { [water] in water.setEnabled($0) })
            )

            if settings.waterReminder {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        SettingLabel(title: "Buddy", info: "Who brings the bottle. **Random** picks one each time.")
                        Spacer(minLength: 8)
                        Picker("Buddy", selection: $settings.waterTheme) {
                            ForEach(WaterTheme.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .settingRowPadding(isIndented: true)
                    Stepper(value: intervalBinding, in: Self.intervals, step: 5) {
                        labeled("Remind every", WaterReminder.format(minutes: settings.waterReminderMinutes))
                    }
                    .controlSize(.small)
                    .settingRowPadding(isIndented: true)
                    Stepper(value: $settings.waterDailyGoal, in: 1...20) {
                        labeled("Daily goal", "\(settings.waterDailyGoal) glasses")
                    }
                    .controlSize(.small)
                    .settingRowPadding(isIndented: true)
                    HStack(spacing: 8) {
                        SettingLabel(title: "Snooze for", info: "How long **Snooze** on a reminder waits before asking again.")
                        Spacer(minLength: 8)
                        Picker("Snooze for", selection: $settings.waterSnoozeMinutes) {
                            ForEach(Self.snoozeOptions, id: \.self) { Text(WaterReminder.format(minutes: $0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .settingRowPadding(isIndented: true)
                    SettingStatus(status, isIndented: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            GroupDivider()
            SettingRow(
                "Now playing",
                info: "Album art and playback controls for Music, Spotify or a browser tab, in the notch's hover panel.",
                isOn: Binding(get: { settings.nowPlaying }, set: { [nowPlaying] in nowPlaying.setEnabled($0) })
            )

            if settings.nowPlaying {
                VStack(alignment: .leading, spacing: 0) {
                    SettingRow(
                        "Show while closed",
                        info: "Artwork and a live equalizer beside the closed notch while music plays.",
                        isOn: $settings.nowPlayingInClosedNotch,
                        isIndented: true
                    )
                    SettingStatus(nowPlayingStatus.text, tone: nowPlayingStatus.tone, isIndented: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.waterReminder)
        .animation(.snappy(duration: 0.25), value: settings.nowPlaying)
    }

    private var nowPlayingStatus: (text: String, tone: SettingStatus.Tone) {
        if let error = nowPlaying.setupError { return (error, .error) }
        guard let track = nowPlaying.track else { return ("Nothing playing", .normal) }
        let source = track.appName.map { " · \($0)" } ?? ""
        return ("\(track.isPlaying ? "Playing" : "Paused"): \(track.title)\(source)", .normal)
    }

    private var intervalBinding: Binding<Int> {
        Binding(get: { settings.waterReminderMinutes }, set: { [water] in water.setInterval(minutes: $0) })
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }

    private var status: String {
        let today = "\(water.glassesToday) of \(settings.waterDailyGoal) glasses today"
        guard let next = water.nextReminder, water.state == .away else { return today }
        return "\(today) · next at \(next.formatted(date: .omitted, time: .shortened))"
    }
}

extension ExtrasSection {
    var summary: String {
        let switches = [settings.waterReminder, settings.nowPlaying]
        return "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}
