import SwiftUI

/// The two behaviors people flip most often, right inside the notch.
struct QuickSettingsView: View {
    @Bindable var settings: AppSettings
    let onSetAutoAllow: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick settings")
                    .font(Theme.Typeface.micro)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                IconButton(systemName: "xmark", help: "Hide from the notch (still in the menu bar settings)") {
                    withAnimation(Theme.Motion.content) { settings.showQuickSettingsInNotch = false }
                }
                .padding(.trailing, -6)
                .padding(.vertical, -6)
            }

            IslandToggleRow(
                title: "Auto-allow permissions",
                caption: settings.askForRiskyCommands ? "Risky commands still ask" : "Everything is approved",
                symbol: "bolt.fill",
                isOn: Binding(get: { settings.autoAllowPermissions }, set: { [onSetAutoAllow] in onSetAutoAllow($0) })
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settings.questionMode == .off ? Theme.Palette.textTertiary : Theme.Palette.clay)
                        .frame(width: 16)
                    Text("Claude's questions")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(settings.questionMode.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
                IslandSegmented(options: QuestionMode.allCases, selection: $settings.questionMode, title: \.title)
                    .padding(.leading, 26)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 0.5)
        )
    }
}
