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

    /// What the player takes right now, plus the shuffle and repeat modes its
    /// commands carry (not every player puts them in the now-playing info).
    struct Commands {
        /// Enabled `MediaRemoteCommand` values, as raw numbers.
        var supported: [Int] = []
        var shuffleMode: Int?
        var repeatMode: Int?
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
    /// Keys in a command's options holding the current modes.
    private let shuffleModeKey: String?
    private let repeatModeKey: String?
    let notificationNames: [Notification.Name]

    init?() {
        guard let handle = dlopen(Self.path, RTLD_NOW) else { return nil }
        func function<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        func constant(_ name: String) -> String? {
            dlsym(handle, name).map { $0.assumingMemoryBound(to: CFString.self).pointee as String }
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
        shuffleModeKey = constant("kMRMediaRemoteCommandInfoShuffleMode")
        repeatModeKey = constant("kMRMediaRemoteCommandInfoRepeatMode")
        let notifications: [String] = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteSupportedCommandsDidChangeNotification",
        ]
        notificationNames = notifications.compactMap { constant($0).map { Notification.Name($0) } }
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

    func supportedCommands() -> Commands {
        guard let list = classCall("localSupportedCommands") as? [NSObject] else { return Commands() }
        var commands = Commands()
        for info in list {
            if let options = value("options", of: info) as? [String: Any] {
                commands.shuffleMode = commands.shuffleMode ?? Self.mode(shuffleModeKey, in: options)
                commands.repeatMode = commands.repeatMode ?? Self.mode(repeatModeKey, in: options)
            }
            guard (value("enabled", of: info) as? NSNumber)?.boolValue ?? true,
                  let command = value("command", of: info) as? NSNumber else { continue }
            commands.supported.append(command.intValue)
        }
        commands.supported.sort()
        return commands
    }

    /// A shuffle or repeat mode; 0 means the player doesn't know.
    static func mode(_ key: String?, in dictionary: [String: Any]) -> Int? {
        guard let key, let mode = (dictionary[key] as? NSNumber)?.intValue, mode > 0 else { return nil }
        return mode
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
