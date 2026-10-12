import SwiftUI

/// Top of a session's reply dropdown: the conversation so far, scrolled to
/// the latest message. Your prompts sit on the right, Claude's replies on the left.
struct ConversationHistoryView: View {
    let sessionID: String
    let transcriptPath: String?

    static let maxHeight: CGFloat = 240
    private static let bottomID = "conversation-bottom"

    private enum LoadState: Equatable {
        case loading
        case unavailable
        case loaded([ConversationMessage])
    }

    @State private var state: LoadState = .loading
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Group {
            switch state {
            case .loaded(let messages) where !messages.isEmpty:
                transcript(messages)
            case .loaded:
                placeholder("No messages yet.")
            case .unavailable:
                placeholder("This session's conversation couldn't be read.")
            case .loading:
                placeholder("Loading conversation…")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .task(id: "\(sessionID)|\(transcriptPath ?? "")") { await watch() }
    }

    private func transcript(_ messages: [ConversationMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                // Not lazy: a lazy stack reports an estimated height, which left
                // the box blank until it was scrolled.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    Color.clear.frame(height: 0).id(Self.bottomID)
                }
                .padding(10)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
            // Full height until the content is measured, so it never shows as an empty sliver.
            .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxHeight) : Self.maxHeight)
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: messages) { old, new in
                guard old.last != new.last || old.count != new.count else { return }
                withAnimation(Theme.Motion.content) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    /// Keeps the history in step with the transcript file itself, so what's
    /// typed in Claude Code shows up as well as what's sent from the notch.
    /// Hook events alone aren't enough: they can fire before Claude Code has
    /// written the line they're about, and Claude's text between tool calls
    /// has no hook at all.
    private func watch() async {
        let id = sessionID
        let path = transcriptPath
        var lastStamp: SessionTranscript.Stamp?
        while !Task.isCancelled {
            let previous = lastStamp
            let result = await Task.detached(priority: .utility) { () -> (SessionTranscript.Stamp?, LoadState?) in
                // Looked up each pass: the file may not exist yet on a brand-new session.
                guard let url = SessionTranscript.url(sessionID: id, reportedPath: path) else { return (nil, .unavailable) }
                let stamp = SessionTranscript.stamp(of: url)
                if let stamp, stamp == previous { return (stamp, nil) }
                return (stamp, SessionTranscript.messages(in: url).map(LoadState.loaded) ?? .unavailable)
            }.value
            guard !Task.isCancelled else { return }
            lastStamp = result.0
            if let next = result.1, next != state { state = next }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.Palette.clay.opacity(0.22))
                    )
            }
        case .claude:
            HStack(alignment: .top, spacing: 8) {
                ClaudeSpark(size: 11, isActive: false)
                    .padding(.top, 3)
                MarkdownText(source: message.text)
            }
        }
    }
}
