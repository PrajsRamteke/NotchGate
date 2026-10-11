import Foundation

/// Sample sessions for previewing the hover activity panel.
enum DemoActivity {
    static func sessions(now: Date = .now) -> [SessionActivity] {
        var api = SessionActivity(id: "demo-api", cwd: "/Users/demo/checkout-api", claudePID: 0, updatedAt: now)
        api.phase = .running(ToolStep(
            toolName: "Bash", summary: "Running the integration tests", symbol: "terminal", startedAt: now
        ))
        api.prompt = "Add retry with backoff to the payment client and cover it with tests"
        api.toolCount = 14
        api.turnStartedAt = now.addingTimeInterval(-134)
        api.tasks = [
            TaskItem(id: "1", title: "Read payment client", activeTitle: nil, status: .completed),
            TaskItem(id: "2", title: "Add backoff policy", activeTitle: nil, status: .completed),
            TaskItem(id: "3", title: "Write tests", activeTitle: "Writing tests for retries", status: .inProgress),
            TaskItem(id: "4", title: "Update docs", activeTitle: nil, status: .pending),
        ]

        var web = SessionActivity(id: "demo-web", cwd: "/Users/demo/dashboard", claudePID: 0, updatedAt: now.addingTimeInterval(-40))
        web.phase = .waiting(reason: "Needs permission · Running npm install")
        web.prompt = "Upgrade the chart library"
        web.toolCount = 3
        web.turnStartedAt = now.addingTimeInterval(-52)

        var docs = SessionActivity(id: "demo-docs", cwd: "/Users/demo/handbook", claudePID: 0, updatedAt: now.addingTimeInterval(-300))
        docs.phase = .finished
        docs.lastMessage = "Rewrote the onboarding guide and fixed 6 broken links."
        docs.turnStartedAt = now.addingTimeInterval(-420)
        docs.turnEndedAt = now.addingTimeInterval(-300)
        docs.toolCount = 9

        return [api, web, docs]
    }
}
