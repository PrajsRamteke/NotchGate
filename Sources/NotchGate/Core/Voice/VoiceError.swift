import Foundation

/// Everything that can stop a dictation, each with a short line for the pill and a
/// fuller one for the settings.
enum VoiceError: Error, Equatable, Sendable {
    case microphoneDenied
    case accessibilityDenied
    case speechRecognitionDenied
    case noMicrophone
    case microphoneFailed(String)
    case microphoneChanged
    case languageUnsupported(String)
    case modelDownloadFailed(String)
    case notReady
    case recognitionFailed(String)
    case timedOut
    /// Run from `swift run`: macOS only grants the microphone to the bundled app.
    case unbundled

    /// One line for the pill.
    var title: String {
        switch self {
        case .microphoneDenied: return "Microphone access is off"
        case .accessibilityDenied: return "Accessibility access is off"
        case .speechRecognitionDenied: return "Speech Recognition access is off"
        case .noMicrophone: return "No microphone found"
        case .microphoneFailed: return "The microphone didn't start"
        case .microphoneChanged: return "The microphone changed"
        case .languageUnsupported: return "This language isn't supported"
        case .modelDownloadFailed: return "The speech model didn't download"
        case .notReady: return "Still getting ready"
        case .recognitionFailed: return "Couldn't transcribe that"
        case .timedOut: return "Transcribing took too long"
        case .unbundled: return "Run NotchGate.app for voice"
        }
    }

    /// What happened and what to do, for the settings.
    var detail: String {
        switch self {
        case .microphoneDenied:
            return "Allow \(VoicePermissions.appName) in System Settings → Privacy & Security → Microphone."
        case .accessibilityDenied:
            return "Allow \(VoicePermissions.appName) in System Settings → Privacy & Security → Accessibility."
        case .speechRecognitionDenied:
            return "Allow \(VoicePermissions.appName) in System Settings → Privacy & Security → Speech Recognition."
        case .noMicrophone:
            return "Connect a microphone or pick one in System Settings → Sound → Input."
        case .microphoneFailed(let reason):
            return "The microphone couldn't start (\(reason)). Check System Settings → Sound → Input."
        case .microphoneChanged:
            return "The input device changed while you were talking. Hold the key again."
        case .languageUnsupported(let language):
            return "On-device speech recognition isn't available for \(language). Pick another language."
        case .modelDownloadFailed(let reason):
            return "Apple's speech model didn't download (\(reason)). Check your connection; NotchGate retries when you turn Notch Voice on again."
        case .notReady:
            return "Notch Voice is still getting its speech model ready."
        case .recognitionFailed(let reason):
            return "Speech recognition failed: \(reason)"
        case .timedOut:
            return "Speech recognition didn't finish in time. Try a shorter dictation."
        case .unbundled:
            return "macOS only gives the microphone to an app, not to a bare binary. Start NotchGate with `make run` (or open NotchGate.app) instead of `swift run`."
        }
    }
}
