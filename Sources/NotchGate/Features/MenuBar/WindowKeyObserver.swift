import AppKit
import SwiftUI

/// Calls `onBecomeKey` each time the hosting window becomes key, e.g. every time
/// the menu-bar window opens (unlike `onAppear`, which fires once per window).
struct WindowKeyObserver: NSViewRepresentable {
    let onBecomeKey: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onBecomeKey: onBecomeKey)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBecomeKey = onBecomeKey
    }

    final class ObserverView: NSView {
        var onBecomeKey: () -> Void

        init(onBecomeKey: @escaping () -> Void) {
            self.onBecomeKey = onBecomeKey
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // Selector-based observers are dropped automatically when the view deallocates.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            if let newWindow {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: newWindow
                )
            }
        }

        @objc private func windowDidBecomeKey(_ note: Notification) {
            onBecomeKey()
        }
    }
}
