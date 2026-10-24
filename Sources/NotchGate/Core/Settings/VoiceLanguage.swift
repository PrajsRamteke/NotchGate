import Foundation

/// The languages offered for Notch Voice. Picking the variant that matches your accent
/// is the biggest accuracy win.
enum VoiceLanguage {
    static let automatic = ""

    static let options: [(id: String, title: String)] = [
        (automatic, "Automatic"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("en-IN", "English (India)"),
        ("en-AU", "English (Australia)"),
        ("en-CA", "English (Canada)"),
        ("en-IE", "English (Ireland)"),
        ("en-NZ", "English (New Zealand)"),
        ("en-SG", "English (Singapore)"),
        ("en-ZA", "English (South Africa)"),
    ]

    /// The chosen language; for automatic, the Mac's own English variant, else US English.
    static func locale(for id: String, current: Locale = .current) -> Locale {
        if id != automatic { return Locale(identifier: id) }
        guard current.language.languageCode == .english, let region = current.region else {
            return Locale(identifier: "en-US")
        }
        return Locale(identifier: "en-\(region.identifier)")
    }

    static func title(for id: String) -> String {
        options.first { $0.id == id }?.title ?? id
    }
}
