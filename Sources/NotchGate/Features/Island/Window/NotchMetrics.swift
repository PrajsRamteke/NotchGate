import AppKit

/// Physical geometry of the notch (or a virtual one on displays without it).
struct NotchMetrics: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool

    static let fallback = NotchMetrics(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchSize: CGSize(width: 185, height: 32),
        hasNotch: false
    )
}

@MainActor
enum ScreenLocator {
    /// Prefers the built-in notched display; otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchMetrics(
                screenFrame: screen.frame,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasNotch: true
            )
        }

        // No notch: emulate one the height of the menu bar.
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchMetrics(
            screenFrame: screen.frame,
            notchSize: CGSize(width: 180, height: menuBarHeight),
            hasNotch: false
        )
    }
}
