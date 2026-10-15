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
        VStack(alignment: .leading, spacing: 8) {
            SettingRow(
                "Water reminder",
                detail: "A little bot or Spidey drops from the notch with a bottle",
                isOn: Binding(get: { settings.waterReminder }, set: { [water] in water.setEnabled($0) })
            )

            if settings.waterReminder {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Buddy").font(.callout)
                        Spacer(minLength: 8)
                        Picker("Buddy", selection: $settings.waterTheme) {
                            ForEach(WaterTheme.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Who brings the bottle. Random picks one each time.")
                    }
                    Stepper(value: intervalBinding, in: Self.intervals, step: 5) {
                        labeled("Remind every", WaterReminder.format(minutes: settings.waterReminderMinutes))
                    }
                    Stepper(value: $settings.waterDailyGoal, in: 1...20) {
                        labeled("Daily goal", "\(settings.waterDailyGoal) glasses")
                    }
                    HStack {
                        Text("Snooze for").font(.callout)
                        Spacer(minLength: 8)
                        Picker("Snooze for", selection: $settings.waterSnoozeMinutes) {
                            ForEach(Self.snoozeOptions, id: \.self) { Text("\($0)m").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingNote(status)
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            SettingRow(
                "Now playing",
                detail: "Artwork and controls for Music, Spotify or a browser tab",
                isOn: Binding(get: { settings.nowPlaying }, set: { [nowPlaying] in nowPlaying.setEnabled($0) })
            )

            if settings.nowPlaying {
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow(
                        "Show while closed",
                        detail: "Artwork and a live equalizer beside the notch while music plays",
                        isOn: $settings.nowPlayingInClosedNotch
                    )
                    SettingNote(nowPlayingStatus)
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.waterReminder)
        .animation(.snappy(duration: 0.25), value: settings.nowPlaying)
    }

    private var nowPlayingStatus: String {
        if let error = nowPlaying.setupError { return error }
        guard let track = nowPlaying.track else {
            return "Nothing playing. Hover the notch to see the player."
        }
        let source = track.appName.map { " in \($0)" } ?? ""
        return "\(track.isPlaying ? "Playing" : "Paused"): \(track.title)\(source). Hover the notch to control it."
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
        return "\(today) · next at \(next.formatted(date: .omitted, time: .shortened)). Waits while you're away from the Mac."
    }
}

extension ExtrasSection {
    var summary: String {
        let switches = [settings.waterReminder, settings.nowPlaying]
        return "\(switches.filter { $0 }.count) of \(switches.count) on"
    }
}
