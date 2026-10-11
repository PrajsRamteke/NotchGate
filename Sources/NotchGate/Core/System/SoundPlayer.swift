import AppKit

/// Subtle audio cues. Uses built-in system sounds so nothing ships in the bundle.
@MainActor
enum SoundPlayer {
    enum Cue: String {
        case arrive = "Tink"
        case resolve = "Pop"
        /// The water bot drops in.
        case water = "Bottle"
        /// A glass logged.
        case sip = "Glass"
        /// The daily water goal reached.
        case goal = "Hero"
    }

    static func play(_ cue: Cue, volume: Float = 0.35) {
        guard let sound = NSSound(named: NSSound.Name(cue.rawValue))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
