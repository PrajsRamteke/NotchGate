import AppKit
import SwiftUI

/// Owns the notch panel: positions it over the notch, keeps it there across
/// display changes, and makes it click-through everywhere except the island.
@MainActor
final class NotchWindowController {
    private let panel = NotchPanel()
    private let viewModel: IslandViewModel
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    /// Keeps the island still during Space swipes (nil if unsupported).
    private var stickySpace: StickySpace?
    private var resignObserver: NSObjectProtocol?

    /// Extra slop around the island so the cursor doesn't flicker at the edge.
    private let hitSlop: CGFloat = 6
    /// Area the island covered when the user last clicked inside it. Clicking a
    /// button can shrink the island out from under the cursor; it stays open
    /// until the cursor leaves this area or the user clicks elsewhere.
    private var heldRect: CGRect?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        let hosting = NSHostingView(rootView: IslandRootView(model: viewModel))
        hosting.sizingOptions = []
        panel.contentView = hosting

        viewModel.onNeedsKeyFocus = { [weak self] in self?.panel.makeKey() }
        viewModel.onIslandFrameChange = { [weak self] in self?.updateHitTesting() }
        // Clicking anywhere else ends typing, which lets the hover panel close.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak viewModel] _ in
            MainActor.assumeIsolated { viewModel?.endComposing() }
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        stickySpace = StickySpace()
        stickySpace?.add(panel)
        startMouseTracking()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        stickySpace?.remove(panel)
        stickySpace = nil
        panel.orderOut(nil)
    }

    // MARK: Layout

    private func reposition() {
        guard let screen = ScreenLocator.preferredScreen() else { return }
        let metrics = ScreenLocator.metrics(for: screen)
        viewModel.notch = metrics

        let size = Theme.Metrics.canvasSize
        let frame = CGRect(
            x: (metrics.screenFrame.midX - size.width / 2).rounded(),
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        Log.window.debug("Positioned island on \(screen.localizedName, privacy: .public)")
    }

    // MARK: Mouse pass-through

    private func startMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                // A click in another app is a click outside the island.
                if event.type == .leftMouseDown { self?.heldRect = nil }
                self?.updateHitTesting()
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown { self?.holdIslandOpenForClick() }
                self?.updateHitTesting()
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// The island's SwiftUI frame (top-left origin, window space) in screen space.
    private var islandScreenRect: CGRect? {
        let island = viewModel.islandFrame
        guard !island.isEmpty else { return nil }
        return CGRect(
            x: panel.frame.minX + island.minX,
            y: panel.frame.maxY - island.maxY,
            width: island.width,
            height: island.height
        ).insetBy(dx: -hitSlop, dy: -hitSlop)
    }

    private func holdIslandOpenForClick() {
        guard let rect = islandScreenRect, rect.contains(NSEvent.mouseLocation) else {
            heldRect = nil
            return
        }
        heldRect = rect
    }

    /// Toggles click-through and hover. Clicks only land on the visible island;
    /// "hovering" also covers the area held open by the last click.
    private func updateHitTesting() {
        // While hidden the island is exactly the notch, so hovering the notch
        // itself is what reveals the activity panel.
        let canHover = viewModel.presentation != .hidden || viewModel.settings.showActivityOnHover
        guard canHover, let rect = islandScreenRect else {
            heldRect = nil
            panel.ignoresMouseEvents = true
            viewModel.setHovering(false)
            return
        }
        let location = NSEvent.mouseLocation
        let overIsland = rect.contains(location)
        let overHeldArea = heldRect?.contains(location) ?? false
        if !overIsland && !overHeldArea { heldRect = nil }

        panel.ignoresMouseEvents = !overIsland
        viewModel.setHovering(overIsland || overHeldArea)
    }
}
