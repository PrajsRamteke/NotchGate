import Foundation

/// Who drops out of the notch with the bottle.
enum WaterCharacter: String, CaseIterable, Sendable {
    /// The ivory-and-clay robot on a braided rope.
    case robot
    /// A little web-slinger hanging upside down on a web line.
    case spidey
}

/// The character picked in Extras: one of them every time, or a surprise.
enum WaterTheme: String, CaseIterable, Identifiable, Sendable {
    case robot
    case spidey
    /// A different character may drop in each time.
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .robot: return "Robot"
        case .spidey: return "Spidey"
        case .random: return "Random"
        }
    }

    /// The character for the next reminder.
    func pick<G: RandomNumberGenerator>(using generator: inout G) -> WaterCharacter {
        switch self {
        case .robot: return .robot
        case .spidey: return .spidey
        case .random: return WaterCharacter.allCases.randomElement(using: &generator) ?? .robot
        }
    }
}
