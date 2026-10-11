import AppKit
import SwiftUI

/// The notch's prompt box for one Claude session: types the message (and any
/// attached images) into that session's terminal, then reports success or
/// explains what went wrong and offers the right next step.
struct NotchComposer: View {
    let controller: ComposerController
    let target: PromptTarget
    var placeholder: String?
    var autofocus = false
    let onFocus: () -> Void
    let onOpenTerminal: () -> Void
    var onDelivered: () -> Void = {}

    @State private var text = ""
    @State private var isSending = false
    @State private var feedback: Feedback?
    /// The message that failed, kept so a fallback action can resend it.
    @State private var failedText = ""

    private enum Feedback: Equatable {
        case success(String)
        case failure(PromptDeliveryError, fallback: HookFallback?)
    }

    private var drafts: ImageDrafts { controller.drafts }

    var body: some View {
        let availability = controller.availability(for: target)
        VStack(alignment: .leading, spacing: 7) {
            if case .unavailable(let reason) = availability {
                unavailableView(reason)
            } else {
                PromptComposer(
                    placeholder: placeholder ?? defaultPlaceholder(availability),
                    text: $text,
                    autofocus: autofocus,
                    isSending: isSending,
                    attachments: drafts.images(for: target.sessionID),
                    onRemoveAttachment: { drafts.remove($0, from: target.sessionID) },
                    onPaste: pasteImages,
                    onFocus: onFocus,
                    onSend: { send($0, force: false) }
                )
                footer(availability)
            }
        }
        .animation(Theme.Motion.content, value: feedback)
    }

    // MARK: Sending

    private func send(_ message: String, force: Bool) {
        isSending = true
        feedback = nil
        Task {
            let outcome = await controller.send(message, to: target, force: force)
            apply(outcome, message: message)
        }
    }

    /// ⌘V with an image on the clipboard attaches it; anything else pastes as text.
    private func pasteImages(from pasteboard: NSPasteboard) -> Bool {
        guard ImageIntake.canRead(pasteboard) else { return false }
        let images = ImageIntake.attachments(from: pasteboard, limit: drafts.remaining(for: target.sessionID))
        drafts.add(images, to: target.sessionID)
        if feedback != nil { feedback = nil }
        return true
    }

    private func sendViaHook(_ message: String) {
        apply(controller.sendViaHook(message, to: target), message: message)
    }

    private func apply(_ outcome: PromptOutcome, message: String) {
        isSending = false
        switch outcome {
        case .typed(let terminal):
            succeed("Sent to \(terminal)")
        case .sentViaHook:
            succeed("Sent to Claude (shows as hook feedback)")
        case .queued:
            succeed("Queued for when Claude finishes")
        case .failed(let error, let fallback):
            failedText = message
            feedback = .failure(error, fallback: fallback)
        }
    }

    private func succeed(_ message: String) {
        text = ""
        feedback = .success(message)
        onDelivered()
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .success(message) = feedback { feedback = nil }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private func footer(_ availability: ComposerAvailability) -> some View {
        switch feedback {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.success)
        case .failure(let error, let fallback):
            failureView(error, fallback: fallback)
        case nil:
            hint(availability)
        }
    }

    private func failureView(_ error: PromptDeliveryError, fallback: HookFallback?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if case .awaitingAnswer = error {
                    LinkButton(title: "Send anyway") { send(failedText, force: true) }
                }
                if fallback == .sendNow {
                    LinkButton(title: "Send via hook instead") { sendViaHook(failedText) }
                } else if fallback == .queue {
                    LinkButton(title: "Queue via hook") { sendViaHook(failedText) }
                }
                LinkButton(title: "Open terminal", action: onOpenTerminal)
            }
        }
    }

    @ViewBuilder
    private func hint(_ availability: ComposerAvailability) -> some View {
        switch availability {
        case .types(let terminal):
            caption("Types into \(terminal) as if you wrote it there.")
        case .hookOnly(let terminal):
            caption("\(terminal) can't be typed into, so this goes through Claude's hook.")
        case .queueOnly(let terminal):
            caption("\(terminal) can't be typed into. Sent through the hook when Claude finishes.")
        case .unavailable:
            EmptyView()
        }
    }

    private func unavailableView(_ reason: String) -> some View {
        HStack(spacing: 8) {
            caption(reason)
            Spacer(minLength: 4)
            LinkButton(title: "Open terminal", action: onOpenTerminal)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func defaultPlaceholder(_ availability: ComposerAvailability) -> String {
        if case .queueOnly = availability { return "Queue a message for when Claude finishes…" }
        return "Message Claude in \(target.projectName)…"
    }
}
