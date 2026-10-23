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
    func line(variant: Int, character: WaterCharacter = .robot) -> String {
        let lines: [String]
        switch character {
        case .robot: lines = robotLines
        case .spidey: lines = spideyLines
        case .batman: lines = batmanLines
        case .developer: lines = developerLines
        }
        return lines[abs(variant) % lines.count]
    }

    private var robotLines: [String] {
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
        return lines
    }

    private var spideyLines: [String] {
        switch self {
        case .cheerful: return ["Thwip! Water time!", "Hang in there… and sip!", "Your friendly hydration hero!"]
        case .excited: return ["My spidey-sense says: drink!", "Ooh, you found me!", "Thwip thwip, let's go!"]
        case .pleading: return ["Pretty please?", "I swung all this way…", "Just one sip, hero?"]
        case .thirsty: return ["Great power, great hydration!", "My web's drying out…", "Even heroes need water!"]
        case .delighted: return ["Thwip-tastic!", "Hydration saved the day!", "Amazing! Spectacular!"]
        case .sleepy: return ["Zzz… hanging around"]
        case .tickled: return ["Hey! Not the web!", "Hehe, spidey-tickles!", "Whoa, I'm spinning!"]
        }
    }

    private var batmanLines: [String] {
        switch self {
        case .cheerful: return ["I'm Batman. Drink water.", "Gotham needs you hydrated.", "Even the night needs water."]
        case .excited: return ["To the water bottle!", "You found me. Now drink.", "Alfred says: hydrate!"]
        case .pleading: return ["One sip, citizen.", "Don't make me ask twice.", "I came all this way…"]
        case .thirsty: return ["Why so thirsty?", "My utility belt is dry…", "This city is parched."]
        case .delighted: return ["Justice… and hydration!", "Mission accomplished.", "Alfred would be proud."]
        case .sleepy: return ["Zzz… on patrol"]
        case .tickled: return ["Hey! Not the cape!", "Batman doesn't giggle.", "That's classified!"]
        }
    }

    private var developerLines: [String] {
        switch self {
        case .cheerful: return ["Coffee isn't water. Sadly.", "Sip break, then ship.", "Hydrate before you deploy.", "git commit -m \"drink\""]
        case .excited: return ["sudo drink water", "Oh hi! Water break?", "Yes! Merge that sip!"]
        case .pleading: return ["Stuck at 99%… need water.", "One sip? I'll fix the bug after.", "Hydrated devs ship faster."]
        case .thirsty: return ["Error 404: water not found", "Running on coffee fumes…", "My brain is buffering…"]
        case .delighted: return ["200 OK!", "Build passed. Hydrated.", "Rebooted and refreshed!"]
        case .sleepy: return ["Zzz… compiling"]
        case .tickled: return ["Hey! I'm not a bug!", "Hehe, it's a feature!", "Ctrl+Z! Ctrl+Z!"]
        }
    }
}
