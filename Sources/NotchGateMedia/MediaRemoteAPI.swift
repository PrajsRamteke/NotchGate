import Foundation
import NotchGateKit

/// The private MediaRemote framework, looked up at runtime. Its C functions
/// and the `MRNowPlayingRequest` class have been stable since macOS 10.12 / 15.
struct MediaRemoteAPI: @unchecked Sendable {
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias InfoHandler = @convention(block) (NSDictionary?) -> Void
    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping InfoHandler) -> Void
    private typealias PlayingHandler = @convention(block) (Bool) -> Void
    private typealias GetPlaying = @convention(c) (DispatchQueue, @escaping PlayingHandler) -> Void
    private typealias SendCommand = @convention(c) (Int32, NSDictionary?) -> Bool
    private typealias SetDouble = @convention(c) (Double) -> Void
    private typealias SetMode = @convention(c) (Int32) -> Void
    /// A class method that takes no arguments and returns an object.
    private typealias ClassGetter = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?

    struct Client {
        var bundleID: String?
        var parentBundleID: String?
        var name: String?
    }

    private static let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    private let register: Register
    private let getInfo: GetInfo
    private let getPlaying: GetPlaying
    private let sendCommand: SendCommand
    private let setElapsed: SetDouble
    private let setShuffle: SetMode?
    private let setRepeat: SetMode?
    /// `MRNowPlayingRequest`, for the player's app and its supported commands.
    private let request: AnyClass?
    let notificationNames: [Notification.Name]

    init?() {
        guard let handle = dlopen(Self.path, RTLD_NOW) else { return nil }
        func function<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let register = function("MRMediaRemoteRegisterForNowPlayingNotifications", as: Register.self),
              let getInfo = function("MRMediaRemoteGetNowPlayingInfo", as: GetInfo.self),
              let getPlaying = function("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetPlaying.self),
              let sendCommand = function("MRMediaRemoteSendCommand", as: SendCommand.self),
              let setElapsed = function("MRMediaRemoteSetElapsedTime", as: SetDouble.self)
        else { return nil }
        self.register = register
        self.getInfo = getInfo
        self.getPlaying = getPlaying
        self.sendCommand = sendCommand
        self.setElapsed = setElapsed
        setShuffle = function("MRMediaRemoteSetShuffleMode", as: SetMode.self)
        setRepeat = function("MRMediaRemoteSetRepeatMode", as: SetMode.self)
        request = NSClassFromString("MRNowPlayingRequest")
        let notifications: [String] = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteSupportedCommandsDidChangeNotification",
        ]
        notificationNames = notifications.compactMap { symbol in
            dlsym(handle, symbol).map { Notification.Name($0.assumingMemoryBound(to: CFString.self).pointee as String) }
        }
    }

    func registerForNotifications(_ queue: DispatchQueue) {
        register(queue)
    }

    func nowPlayingInfo(on queue: DispatchQueue, _ completion: @escaping ([String: Any]) -> Void) {
        getInfo(queue) { info in completion(info as? [String: Any] ?? [:]) }
    }

    func isPlaying(on queue: DispatchQueue, _ completion: @escaping (Bool) -> Void) {
        getPlaying(queue) { completion($0) }
    }

    func send(_ command: MediaRemoteCommand) -> Bool {
        sendCommand(Int32(command.rawValue), nil)
    }

    func setElapsedTime(_ seconds: Double) {
        setElapsed(seconds)
    }

    func setShuffleMode(_ mode: Int) {
        setShuffle?(Int32(mode))
    }

    func setRepeatMode(_ mode: Int) {
        setRepeat?(Int32(mode))
    }

    /// The app behind the current player.
    func client() -> Client {
        guard let path = classCall("localNowPlayingPlayerPath"),
              let client = value("client", of: path) as? NSObject else { return Client() }
        return Client(
            bundleID: value("bundleIdentifier", of: client) as? String,
            parentBundleID: value("parentApplicationBundleIdentifier", of: client) as? String,
            name: value("displayName", of: client) as? String
        )
    }

    /// Enabled `MediaRemoteCommand` values, as raw numbers.
    func supportedCommands() -> [Int] {
        guard let list = classCall("localSupportedCommands") as? [NSObject] else { return [] }
        return list.compactMap { info in
            guard (value("enabled", of: info) as? NSNumber)?.boolValue ?? true,
                  let command = value("command", of: info) as? NSNumber else { return nil }
            return command.intValue
        }
        .sorted()
    }

    // MARK: Objective-C plumbing (every selector is checked first: a wrong guess must not crash)

    private func classCall(_ name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let request, let method = class_getClassMethod(request, selector) else { return nil }
        let getter = unsafeBitCast(method_getImplementation(method), to: ClassGetter.self)
        return getter(request, selector)?.takeUnretainedValue() as? NSObject
    }

    private func value(_ key: String, of object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}
