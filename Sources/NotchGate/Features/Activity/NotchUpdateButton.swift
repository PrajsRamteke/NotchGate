import SwiftUI

/// Small "Update" pill in the Activity header; only shown while a newer NotchGate exists.
struct NotchUpdateButton: View {
    let updates: UpdateChecker

    private var isUpdating: Bool { updates.state == .updating }

    var body: some View {
        Button {
            Task { await updates.update() }
        } label: {
            HStack(spacing: 4) {
                if isUpdating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text(isUpdating ? "Updating…" : "Update")
                    .lineLimit(1)
            }
            .fixedSize()
            .font(Theme.Typeface.micro)
            .foregroundStyle(Theme.Palette.clay)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.Palette.clay.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .help("A newer NotchGate is available")
        .accessibilityLabel(isUpdating ? "Updating NotchGate" : "Update NotchGate")
    }
}
