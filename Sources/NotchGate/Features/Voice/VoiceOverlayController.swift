import AppKit
import SwiftUI

/// The floating pill at the bottom centre of the screen that shows Notch Voice
/// listening, transcribing and done. Click-through and never takes focus, so the
/// text still lands in the app you were typing in.
@MainActor
final class VoiceOverlayController {
    static let canvasSize = CGSize(width: 640, height: 110)
    /// Gap between the pill and the Dock or the bottom of the screen.
    static let bottomMargin: CGFloat = 10

    private weak var dictation: VoiceDictation?
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    init(dictation: VoiceDictation) {
        self.dictation = dictation
    }

    /// Creates the (hidden) window ahead of time, so the pill animates in the first time too.
    func prepare() {
        guard panel == nil, let dictation else { return }
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: VoiceOverlayView(dictation: dictation))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
    }

    /// Shows or hides the window to match the dictation's phase.
    func update() {
        guard let dictation else { return }
        if dictation.phase == .idle {
            // Let the pill's exit animation play before the window goes.
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.panel?.orderOut(nil)
            }
            return
        }
        hideTask?.cancel()
        prepare()
        guard let panel, !panel.isVisible else { return }
        position(panel)
        panel.orderFrontRegardless()
    }

    /// Bottom centre of the screen you're working on (the one with the pointer), above the Dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: (visible.midX - Self.canvasSize.width / 2).rounded(),
            y: (visible.minY + Self.bottomMargin).rounded()
        )
        panel.setFrame(CGRect(origin: origin, size: Self.canvasSize), display: false)
    }
}

/// The window's content: the pill, animated in and out at the bottom.
struct VoiceOverlayView: View {
    let dictation: VoiceDictation

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if dictation.phase != .idle {
                VoicePill(phase: dictation.phase, levels: dictation.levels, liveText: dictation.liveText)
                    .padding(.bottom, 14)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.55, anchor: .bottom).combined(with: .opacity),
                            removal: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(width: VoiceOverlayController.canvasSize.width, height: VoiceOverlayController.canvasSize.height)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dictation.phase == .idle)
    }
}
