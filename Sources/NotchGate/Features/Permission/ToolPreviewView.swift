import SwiftUI

/// Renders the right preview for a tool request.
struct ToolPreviewView: View {
    let preview: ToolDescriptor.Preview

    var body: some View {
        switch preview {
        case .command(let command):
            CodeBlock(code: command, maxHeight: 120, prompt: "›")
        case .diff(_, let removed, let added):
            DiffPreviewView(removed: removed, added: added)
        case .content(_, let text):
            CodeBlock(code: Self.truncate(text), maxHeight: 160)
        case .json(let value):
            CodeBlock(code: Self.truncate(value.prettyPrinted()), caption: "Arguments", maxHeight: 140)
        case .none:
            EmptyView()
        }
    }

    /// Keeps enormous payloads (e.g. writing a 5 000-line file) snappy.
    private static func truncate(_ text: String, limit: Int = 6_000) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…"
    }
}
