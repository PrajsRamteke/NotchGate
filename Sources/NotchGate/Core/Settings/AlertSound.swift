import Foundation

/// The sound picked for one of Claude's cues: an alert sound built into
/// macOS (so nothing ships in the bundle), or none.
enum AlertSound: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    /// The sounds themselves, for the picker under its "None".
    static let sounds = allCases.filter { $0 != .none }
}
