import AppKit
import SwiftUI

/// Message field with a round send button: ⏎ sends, ⇧⏎ adds a line.
/// The caller owns the text and clears it once delivery succeeds.
///
/// Attached images show as thumbnails above the field; with `onPaste`, ⌘V
/// with an image on the clipboard attaches it instead of pasting text.
struct PromptComposer: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    var isSending = false
    var attachments: [ImageAttachment] = []
    var onRemoveAttachment: (ImageAttachment) -> Void = { _ in }
    var onPaste: ((NSPasteboard) -> Bool)?
    let onFocus: () -> Void
    let onSend: (String) -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { (!trimmed.isEmpty || !attachments.isEmpty) && !isSending }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments: attachments, isEnabled: !isSending, onRemove: onRemoveAttachment)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .bottom, spacing: 8) {
                ReplyField(
                    placeholder: placeholder,
                    text: $text,
                    lineLimit: 1...6,
                    autofocus: autofocus,
                    onSubmit: send,
                    onFocus: onFocus,
                    onPaste: onPaste
                )
                .disabled(isSending)
                SendButton(isEnabled: canSend, isSending: isSending, action: send)
                    .padding(.bottom, 3)
            }
        }
        .animation(Theme.Motion.content, value: attachments)
    }

    private func send() {
        guard canSend else { return }
        onSend(trimmed)
    }
}

/// Thumbnails of the images going out with the next prompt, each removable.
struct AttachmentStrip: View {
    let attachments: [ImageAttachment]
    var isEnabled = true
    let onRemove: (ImageAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment, isEnabled: isEnabled) { onRemove(attachment) }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            // Room for the remove buttons that poke out of each corner.
            .padding(.top, 5)
            .padding(.trailing, 5)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct AttachmentThumbnail: View {
    let attachment: ImageAttachment
    let isEnabled: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    private static let size: CGFloat = 46

    var body: some View {
        Image(nsImage: attachment.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovered ? Theme.Palette.clay.opacity(0.6) : Theme.Palette.hairline, lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isEnabled && isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(Theme.Palette.ivory)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.black.opacity(0.85)))
                            .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Remove image")
                    .accessibilityLabel("Remove image")
                    .transition(.opacity)
                }
            }
            .help(attachment.url.lastPathComponent)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .accessibilityLabel("Attached image")
    }
}

/// Circular clay "arrow up" button, the universal send affordance.
struct SendButton: View {
    let isEnabled: Bool
    var isSending = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSending {
                    ProgressView().controlSize(.mini).tint(Theme.Palette.ivory)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isEnabled ? Theme.Palette.ivory : Theme.Palette.textTertiary)
                }
            }
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(isEnabled || isSending
                    ? AnyShapeStyle(LinearGradient(
                        colors: [isHovered ? Theme.Palette.clayGlow : Theme.Palette.clay, Theme.Palette.clayDeep],
                        startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Theme.Palette.surface))
            )
            .shadow(color: isEnabled ? Theme.Palette.clay.opacity(0.35) : .clear, radius: 6, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help("Send (⏎)")
        .accessibilityLabel(isSending ? "Sending" : "Send")
        .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}
