import SwiftUI

/// Top of a session's reply dropdown: the conversation so far, scrolled to
/// the latest message. Your prompts sit on the right, Claude's replies on the left.
struct ConversationHistoryView: View {
    let sessionID: String
    let transcriptPath: String?
    /// Changes whenever the session does, so the history reloads.
    let revision: Date

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
        .task(id: revision) { await reload() }
    }

    private func transcript(_ messages: [ConversationMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    Color.clear.frame(height: 0).id(Self.bottomID)
                }
                .padding(10)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), Self.maxHeight))
            .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: messages.last) { _, _ in
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

    /// Re-reads the transcript, briefly debounced: a busy session sends
    /// several hook events a second.
    private func reload() async {
        if state != .loading {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }
        let id = sessionID
        let path = transcriptPath
        let messages = await Task.detached(priority: .utility) {
            SessionTranscript.url(sessionID: id, reportedPath: path).flatMap(SessionTranscript.messages(in:))
        }.value
        guard !Task.isCancelled else { return }
        state = messages.map(LoadState.loaded) ?? .unavailable
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
