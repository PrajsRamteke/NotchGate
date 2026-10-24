import AppKit
import ApplicationServices
@preconcurrency import AVFoundation
import Observation
import Speech

/// The macOS permissions Notch Voice needs, and how to ask for each.
///
/// - Microphone: to hear you.
/// - Accessibility: to notice the shortcut in other apps and to press ⌘V for you.
/// - Speech Recognition: only for the macOS 14–15 recognizer.
@MainActor
@Observable
final class VoicePermissions {
    enum Status: Equatable {
        case granted
        case notAsked
        case denied
    }

    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"
        case speechRecognition = "Privacy_SpeechRecognition"
    }

    private(set) var microphone: Status = .notAsked
    private(set) var accessibility = false
    private(set) var speechRecognition: Status = .notAsked

    /// How this app appears in System Settings' lists ("NotchGate", or "NotchGate Dev" from `make run`).
    nonisolated static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "NotchGate"
    }

    @ObservationIgnored private var accessibilityRequests = 0

    init() {
        refresh()
    }

    /// Polled while Notch Voice is on, so it only publishes what actually changed.
    func refresh() {
        let microphone: Status = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        let accessibility = AXIsProcessTrusted()
        let speechRecognition: Status = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        if microphone != self.microphone { self.microphone = microphone }
        if accessibility != self.accessibility { self.accessibility = accessibility }
        if speechRecognition != self.speechRecognition { self.speechRecognition = speechRecognition }
    }

    /// Shows macOS's microphone prompt the first time; afterwards only Settings can change it.
    func requestMicrophone() async {
        if microphone == .notAsked {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else if microphone == .denied {
            Self.openSettings(.microphone)
        }
        refresh()
    }

    /// Asking puts NotchGate in System Settings' Accessibility list (switched off) and shows
    /// macOS's "would like to control this computer" prompt, so there's only a switch to
    /// flip, no app to find. Asking again opens the list directly. Takes effect without a restart.
    func requestAccessibility() {
        accessibilityRequests += 1
        accessibility = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if !accessibility, accessibilityRequests > 1 { Self.openSettings(.accessibility) }
    }

    func requestSpeechRecognition() async {
        if speechRecognition == .notAsked {
            _ = await Self.askForSpeechRecognition()
        } else if speechRecognition == .denied {
            Self.openSettings(.speechRecognition)
        }
        refresh()
    }

    /// macOS answers on a background queue, so the callback is built off the main actor.
    private nonisolated static func askForSpeechRecognition() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    static func openSettings(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
