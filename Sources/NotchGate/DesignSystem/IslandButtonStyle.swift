import SwiftUI

/// Capsule buttons tuned for the dark island.
struct IslandButtonStyle: ButtonStyle {
    enum Role {
        /// Clay-filled call to action (Allow, Approve, Submit).
        case primary
        /// Quiet translucent fill (Always allow, Answer in terminal).
        case secondary
        /// Secondary styling that warms to red on hover (Deny, Reject).
        case destructive
    }

    var role: Role = .secondary
    var shortcut: String?

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, role: role, shortcut: shortcut)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let role: Role
        let shortcut: String?

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            HStack(spacing: 6) {
                configuration.label
                if let shortcut {
                    KeyHint(shortcut, tint: role == .primary ? Theme.Palette.ivory.opacity(0.75) : nil)
                }
            }
            .font(Theme.Typeface.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: Theme.Metrics.buttonHeight)
            .background {
                if role == .primary {
                    Capsule().fill(background).shadow(color: glow, radius: isHovered ? 12 : 6, y: 2)
                } else {
                    Capsule().fill(background)
                }
            }
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { isHovered = $0 && isEnabled }
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }

        private var foreground: Color {
            switch role {
            case .primary: return Theme.Palette.ivory
            case .secondary: return Theme.Palette.textPrimary
            case .destructive: return isHovered ? Theme.Palette.danger : Theme.Palette.textPrimary
            }
        }

        private var background: AnyShapeStyle {
            switch role {
            case .primary:
                let top = isHovered ? Theme.Palette.clayGlow : Theme.Palette.clay
                return AnyShapeStyle(LinearGradient(
                    colors: [top, Theme.Palette.clayDeep],
                    startPoint: .top, endPoint: .bottom
                ))
            case .secondary:
                return AnyShapeStyle(isHovered ? Theme.Palette.surfaceRaised : Theme.Palette.surface)
            case .destructive:
                return AnyShapeStyle(isHovered ? Theme.Palette.danger.opacity(0.14) : Theme.Palette.surface)
            }
        }

        private var stroke: Color {
            role == .primary ? Color.white.opacity(0.18) : Theme.Palette.hairline
        }

        private var glow: Color {
            role == .primary && isEnabled ? Theme.Palette.clay.opacity(isHovered ? 0.45 : 0.25) : .clear
        }
    }
}

extension ButtonStyle where Self == IslandButtonStyle {
    static func island(_ role: IslandButtonStyle.Role = .secondary, shortcut: String? = nil) -> IslandButtonStyle {
        IslandButtonStyle(role: role, shortcut: shortcut)
    }
}

/// Borderless icon button for header chrome (collapse, open terminal).
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isHovered ? Theme.Palette.surfaceRaised : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
