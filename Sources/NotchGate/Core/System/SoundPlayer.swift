import AppKit

/// Subtle audio cues. Uses built-in system sounds so nothing ships in the bundle.
@MainActor
enum SoundPlayer {
    enum Cue: String {
        case resolve = "Pop"
        /// The water bot drops in.
        case water = "Bottle"
        /// A glass logged.
        case sip = "Glass"
        /// The daily water goal reached.
        case goal = "Hero"
    }

    /// How loud the picked sounds play; the settings preview uses the same.
    static let attentionVolume: Float = 0.35
    static let finishedVolume: Float = 0.2

    /// The sound playing from the settings preview, stopped when another starts.
    private static var preview: NSSound?

    static func play(_ cue: Cue, volume: Float = 0.35) {
        play(named: cue.rawValue, volume: volume)
    }

    /// Plays a sound picked in settings; `.none` stays quiet.
    static func play(_ sound: AlertSound, volume: Float) {
        guard sound != .none else { return }
        play(named: sound.rawValue, volume: volume)
    }

    /// Plays a sound from the settings picker, cutting off the last one so
    /// stepping through the list doesn't pile them up.
    static func preview(_ sound: AlertSound, volume: Float) {
        preview?.stop()
        preview = sound == .none ? nil : play(named: sound.rawValue, volume: volume)
    }

    @discardableResult
    private static func play(named name: String, volume: Float) -> NSSound? {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return nil }
        sound.volume = volume
        sound.play()
        return sound
    }
}
