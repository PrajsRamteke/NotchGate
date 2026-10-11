import Foundation
import NotchGateKit
import Testing
@testable import NotchGate

@Suite("Feature models")
@MainActor
struct FeatureModelTests {
    private func prompt(multiSelect: Bool) -> QuestionPrompt {
        QuestionPrompt(
            questions: [Question(
                header: nil,
                text: "Which?",
                options: [.init(label: "A", detail: nil), .init(label: "B", detail: nil), .init(label: "C", detail: nil)],
                multiSelect: multiSelect
            )],
            originalInput: .object(["questions": .array([])])
        )
    }

    @Test func singleSelectReplacesChoice() {
        let form = QuestionFormModel(prompt: prompt(multiSelect: false))
        #expect(form.answers == nil)
        form.toggle(.init(label: "A", detail: nil))
        form.toggle(.init(label: "B", detail: nil))
        #expect(form.answers == ["Which?": "B"])
    }

    @Test func multiSelectJoinsInPresentedOrderWithOther() {
        let form = QuestionFormModel(prompt: prompt(multiSelect: true))
        form.toggle(.init(label: "C", detail: nil))
        form.toggle(.init(label: "A", detail: nil))
        form.toggleOther()
        form.otherText["Which?"] = "  D  "
        #expect(form.answers == ["Which?": "A, C, D"])
    }

    @Test func answersAreMergedIntoToolInput() {
        let input = prompt(multiSelect: false).input(withAnswers: ["Which?": "A"])
        #expect(input["answers"] == .object(["Which?": .string("A")]))
        #expect(input["questions"] != nil)
    }

    @Test func elicitationValidatesAndTypesValues() {
        let form = ElicitationFormModel(prompt: ElicitationPrompt(
            server: "srv", message: "", url: nil,
            fields: [
                ElicitationField(id: "name", title: "Name", detail: nil, kind: .text, isRequired: true, defaultValue: nil),
                ElicitationField(id: "count", title: "Count", detail: nil, kind: .integer, isRequired: false, defaultValue: .number(2)),
                ElicitationField(id: "ok", title: "OK", detail: nil, kind: .boolean, isRequired: false, defaultValue: .bool(true)),
            ]
        ))
        #expect(!form.isValid)
        form.text["name"] = "alice"
        #expect(form.isValid)
        #expect(form.content == .object(["name": .string("alice"), "count": .number(2), "ok": .bool(true)]))
        form.text["count"] = "two"
        #expect(!form.isValid)
    }

    @Test func mcpToolNamesSplitOnDoubleUnderscore() {
        let descriptor = ToolDescriptor.describe(ToolPermission(
            toolName: "mcp__claude_ai_Gmail__send_message", input: .object([:]), suggestions: []
        ))
        #expect(descriptor.title == "Use send_message?")
        #expect(descriptor.subtitle == "from the claude_ai_Gmail MCP server")
    }

    @Test func markdownBlocksParse() {
        let blocks = MarkdownBlock.parse("## Title\n1. First\n- Bullet\n```\ncode\n```\nText")
        #expect(blocks == [
            .heading(level: 2, text: "Title"),
            .bullet(marker: "1.", text: "First"),
            .bullet(marker: "•", text: "Bullet"),
            .code("code"),
            .paragraph("Text"),
        ])
    }
}
