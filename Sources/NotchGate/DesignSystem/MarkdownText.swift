import SwiftUI

/// Lightweight block-level Markdown renderer for plans and summaries.
///
/// Handles headings, bullets, numbered items, fenced code and paragraphs;
/// inline styles (bold, italics, `code`, links) come from `AttributedString`.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text, font: level <= 2 ? Theme.Typeface.title : Theme.Typeface.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.top, level <= 2 ? 4 : 2)
        case .bullet(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.clay)
                    .frame(minWidth: 12, alignment: .trailing)
                inline(text).foregroundStyle(Theme.Palette.textSecondary)
            }
        case .code(let text):
            CodeBlock(code: text, maxHeight: 160)
        case .paragraph(let text):
            inline(text).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func inline(_ text: String, font: Font = Theme.Typeface.body) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return Text(attributed).font(font)
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(marker: String, text: String)
    case code(String)
    case paragraph(String)

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var codeLines: [String]?

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let lines = codeLines {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines = []
                }
                continue
            }
            if codeLines != nil { codeLines?.append(rawLine); continue }
            guard !line.isEmpty else { continue }

            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#") {
                let level = line.distance(from: line.startIndex, to: hashes)
                blocks.append(.heading(level: level, text: String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(marker: "•", text: String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty {
                let text = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                blocks.append(.bullet(marker: String(line[...dot]), text: text))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        if let lines = codeLines { blocks.append(.code(lines.joined(separator: "\n"))) }
        return blocks
    }
}
