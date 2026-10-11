import AppKit
import SwiftUI

@main
struct NotchGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: appDelegate.coordinator)
        } label: {
            Image(nsImage: appDelegate.coordinator.updates.isUpdateAvailable ? MenuBarIcon.badgedImage : MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon, never steals focus on launch.
        NSApp.setActivationPolicy(.accessory)
        if CommandLineActions.runIfRequested() { return }
        LaunchAtLogin.enableByDefault()
        coordinator.start()
        Log.app.info("NotchGate started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
