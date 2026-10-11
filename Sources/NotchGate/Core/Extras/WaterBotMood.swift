import Foundation

/// The water bot's face and voice. It starts cheerful and grows more
/// insistent the longer the reminder is ignored.
enum WaterBotMood: CaseIterable, Equatable {
    case cheerful
    /// The cursor is on it: drink or snooze are one click away.
    case excited
    case pleading
    case thirsty
    /// Just watched you drink.
    case delighted
    /// Snoozed, or nobody's at the Mac.
    case sleepy
    /// Poked.
    case tickled

    static let pleadingAfter: TimeInterval = 25
    static let thirstyAfter: TimeInterval = 75

    static func current(
        state: WaterReminder.State,
        waited: TimeInterval,
        isHovered: Bool,
        isUserAway: Bool,
        isTickled: Bool
    ) -> WaterBotMood {
        switch state {
        case .drinking: return .delighted
        case .snoozing: return .sleepy
        case .away, .asking:
            if isTickled { return .tickled }
            if isUserAway { return .sleepy }
            if isHovered { return .excited }
            if waited >= thirstyAfter { return .thirsty }
            return waited >= pleadingAfter ? .pleading : .cheerful
        }
    }

    /// What the speech bubble says. `variant` rotates the wording between reminders.
    func line(variant: Int) -> String {
        let lines: [String]
        switch self {
        case .cheerful: lines = ["Drink water!", "Sip time!", "Hydration break!", "Water o'clock!"]
        case .excited: lines = ["Yes! Grab a sip!", "Ooh, you're here!", "Let's hydrate!"]
        case .pleading: lines = ["Pretty please?", "Just one sip?", "I carried this up here…"]
        case .thirsty: lines = ["I'm wilting here…", "Brains are 75% water!", "Even plants drink…"]
        case .delighted: lines = ["Ahh, refreshing!", "Hydrated!", "Splash-tastic!"]
        case .sleepy: lines = ["Zzz…"]
        case .tickled: lines = ["Hehe, that tickles!", "Boop! Now drink.", "Hey! Water first!"]
        }
        return lines[abs(variant) % lines.count]
    }
}
