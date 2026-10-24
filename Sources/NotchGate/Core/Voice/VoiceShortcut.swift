import AppKit

/// A modifier key Notch Voice can be held on, told apart by side (left ⌥ vs right ⌥),
/// so the other side stays free for everyday shortcuts.
enum ModifierKey: String, CaseIterable, Codable, Comparable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftShift, rightShift
    case leftCommand, rightCommand
    case function

    /// Device-dependent bit of `NSEvent.modifierFlags` (IOKit's `NX_DEVICE…KEYMASK`).
    var deviceMask: UInt {
        switch self {
        case .leftControl: return 0x0000_0001
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .function: return NSEvent.ModifierFlags.function.rawValue
        }
    }

    var symbol: String {
        switch self {
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .leftShift, .rightShift: return "⇧"
        case .leftCommand, .rightCommand: return "⌘"
        case .function: return "fn"
        }
    }

    var name: String {
        switch self {
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .function: return "Fn"
        }
    }

    /// Short keycap label: "Right ⌥", "fn".
    var keycap: String {
        switch self {
        case .function: return "fn"
        case .leftControl, .leftOption, .leftShift, .leftCommand: return "Left \(symbol)"
        default: return "Right \(symbol)"
        }
    }

    /// The keys held according to an event's raw modifier flags.
    static func held(in rawFlags: UInt) -> Set<ModifierKey> {
        Set(allCases.filter { rawFlags & $0.deviceMask != 0 })
    }

    /// Display order: ⌃ ⌥ ⇧ ⌘ fn, as macOS writes shortcuts.
    static func < (lhs: ModifierKey, rhs: ModifierKey) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// The key, or two keys, held down to talk.
struct VoiceShortcut: Equatable, Sendable {
    static let maxKeys = 2
    static let `default` = VoiceShortcut(keys: [.rightOption])!

    let keys: Set<ModifierKey>

    init?(keys: Set<ModifierKey>) {
        guard (1...Self.maxKeys).contains(keys.count) else { return nil }
        self.keys = keys
    }

    /// Saved form: "rightOption" or "leftControl+leftOption".
    init?(storageValue: String) {
        let keys = storageValue.split(separator: "+").map { ModifierKey(rawValue: String($0)) }
        guard !keys.isEmpty, !keys.contains(nil) else { return nil }
        self.init(keys: Set(keys.compactMap { $0 }))
    }

    var storageValue: String { keys.sorted().map(\.rawValue).joined(separator: "+") }

    /// Keycaps in display order, e.g. ["Left ⌃", "Left ⌥"].
    var keycaps: [String] { keys.sorted().map(\.keycap) }

    /// "Right Option" or "Left Control + Left Option".
    var spokenName: String { keys.sorted().map(\.name).joined(separator: " + ") }

    /// Holding Fn alone also triggers the 🌐 key's own action (emoji picker, dictation…).
    var usesFunctionKeyAlone: Bool { keys == [.function] }
}

/// Turns raw key events into "start talking" / "stop" / "never mind", so holding the
/// shortcut is told apart from using the same keys in an ordinary shortcut (⌥←, ⌥-click…).
///
/// The shortcut must be held on its own, with nothing else pressed, for `armDelay`
/// before recording starts. Pressing any other key first means it was a shortcut, not
/// dictation; the keys must then be let go before they can start dictation again.
struct HoldDetector {
    enum Phase: Equatable {
        case idle
        /// The shortcut is down; waiting out `armDelay` before listening.
        case arming
        /// Listening until the shortcut is released.
        case active
        /// The shortcut was used for something else; ignore it until released.
        case blocked
    }

    enum Action: Equatable {
        case startArmTimer
        case cancelArmTimer
        /// Start listening.
        case begin
        /// The shortcut was released: finish and insert.
        case end
        /// Discard what was said.
        case cancel
    }

    static let armDelay: Duration = .milliseconds(180)

    var shortcut: VoiceShortcut
    private(set) var phase: Phase = .idle

    init(shortcut: VoiceShortcut) {
        self.shortcut = shortcut
    }

    /// Modifier keys went down or up.
    mutating func modifiersChanged(to held: Set<ModifierKey>) -> Action? {
        let exact = held == shortcut.keys
        switch phase {
        case .idle:
            guard exact else { return nil }
            phase = .arming
            return .startArmTimer
        case .arming:
            if exact { return nil }
            // Another modifier joined (⌥ then ⇧): an ordinary shortcut.
            phase = held.isSuperset(of: shortcut.keys) ? .blocked : .idle
            return .cancelArmTimer
        case .active:
            if exact { return nil }
            phase = held.isSuperset(of: shortcut.keys) ? .blocked : .idle
            return .end
        case .blocked:
            if !held.isSuperset(of: shortcut.keys) { phase = .idle }
            return nil
        }
    }

    /// A non-modifier key was pressed (e.g. an arrow while ⌥ is down).
    mutating func keyPressed() -> Action? {
        switch phase {
        case .idle, .blocked:
            return nil
        case .arming:
            phase = .blocked
            return .cancelArmTimer
        case .active:
            // Esc throws the recording away. Any other key means the keys were wanted for
            // typing (⌥ + letter types a symbol), so the recording is discarded too.
            phase = .blocked
            return .cancel
        }
    }

    /// The mouse was clicked (⌥-click and friends never start dictation).
    mutating func mousePressed() -> Action? {
        guard phase == .arming else { return nil }
        phase = .blocked
        return .cancelArmTimer
    }

    mutating func armTimerFired() -> Action? {
        guard phase == .arming else { return nil }
        phase = .active
        return .begin
    }

    /// Forgets the current press, e.g. when dictation is switched off mid-hold.
    mutating func reset() {
        phase = .idle
    }
}
