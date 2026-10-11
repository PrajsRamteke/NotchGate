import AppKit
import Darwin

/// Pins windows to a private, always-on-top window-server space so they
/// stay perfectly still while the user swipes between desktops and
/// full-screen apps (instead of sliding out and back in with each Space).
///
/// Uses SkyLight's private `CGSSpace` API, the same technique other notch
/// apps rely on. Every symbol is resolved at runtime: if a future macOS
/// removes any of them, this quietly does nothing and the panel falls back
/// to its normal `canJoinAllSpaces` behavior.
@MainActor
final class StickySpace {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int, CFDictionary?) -> UInt64
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Void
    private typealias SpaceSetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias WindowsSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Void

    private struct API {
        let connection: DefaultConnection
        let create: SpaceCreate
        let destroy: SpaceDestroy
        let setLevel: SpaceSetLevel
        let addWindows: WindowsSpaces
        let removeWindows: WindowsSpaces
        let show: Spaces
        let hide: Spaces
    }

    /// Above everything else on screen, including full-screen apps.
    private static let level = Int32.max

    private let api: API
    private let connection: Int32
    private let space: UInt64
    private var windowNumbers: Set<Int> = []

    init?() {
        guard let api = Self.loadAPI() else {
            Log.window.notice("SkyLight space API unavailable; the island will move with Spaces")
            return nil
        }
        self.api = api
        connection = api.connection()
        // Flag 1 creates a plain user space (other values make Finder draw desktop icons into it).
        space = api.create(connection, 1, nil)
        api.setLevel(connection, space, Self.level)
        api.show(connection, [NSNumber(value: space)] as CFArray)
    }

    /// The window must already be on screen (have a window number).
    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, windowNumbers.insert(number).inserted else { return }
        api.addWindows(connection, [NSNumber(value: number)] as CFArray, [NSNumber(value: space)] as CFArray)
    }

    func remove(_ window: NSWindow) {
        guard windowNumbers.remove(window.windowNumber) != nil else { return }
        api.removeWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: space)] as CFArray)
    }

    deinit {
        let spaces = [NSNumber(value: space)] as CFArray
        api.hide(connection, spaces)
        api.destroy(connection, space)
    }

    private static func loadAPI() -> API? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            return nil
        }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard
            let connection = symbol("_CGSDefaultConnection", as: DefaultConnection.self),
            let create = symbol("CGSSpaceCreate", as: SpaceCreate.self),
            let destroy = symbol("CGSSpaceDestroy", as: SpaceDestroy.self),
            let setLevel = symbol("CGSSpaceSetAbsoluteLevel", as: SpaceSetLevel.self),
            let addWindows = symbol("CGSAddWindowsToSpaces", as: WindowsSpaces.self),
            let removeWindows = symbol("CGSRemoveWindowsFromSpaces", as: WindowsSpaces.self),
            let show = symbol("CGSShowSpaces", as: Spaces.self),
            let hide = symbol("CGSHideSpaces", as: Spaces.self)
        else { return nil }
        return API(
            connection: connection, create: create, destroy: destroy, setLevel: setLevel,
            addWindows: addWindows, removeWindows: removeWindows, show: show, hide: hide
        )
    }
}
