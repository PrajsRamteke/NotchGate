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

        for file in ["RetryPolicy.swift", "RetryPolicyTests.swift"] {
            api.fileChanges.record(.added, path: "/Users/demo/checkout-api/\(file)", linesAdded: 96)
        }
        for file in ["PaymentClient.swift", "Config.swift", "README.md"] {
            api.fileChanges.record(.modified, path: "/Users/demo/checkout-api/\(file)", linesAdded: 18, linesRemoved: 7)
        }
        api.fileChanges.record(.deleted, path: "/Users/demo/checkout-api/LegacyRetry.swift")
        api.toolUsage = toolUsage(now: now, calls: [
            ("Bash", 18), ("Read", 26), ("Edit", 14), ("Grep", 9), ("Write", 2), ("WebFetch", 3), ("Agent", 1),
        ])

        var web = SessionActivity(id: "demo-web", cwd: "/Users/demo/dashboard", claudePID: 0, updatedAt: now.addingTimeInterval(-40))
        web.phase = .waiting(reason: "Needs permission · Running npm install")
        web.prompt = "Upgrade the chart library"
        web.toolCount = 3
        web.turnStartedAt = now.addingTimeInterval(-52)
        web.toolUsage = toolUsage(now: now, calls: [("Read", 6), ("Bash", 2), ("mcp__github__get_issue", 2)])

        var docs = SessionActivity(id: "demo-docs", cwd: "/Users/demo/handbook", claudePID: 0, updatedAt: now.addingTimeInterval(-300))
        docs.phase = .finished
        docs.lastMessage = "Rewrote the onboarding guide and fixed 6 broken links."
        docs.turnStartedAt = now.addingTimeInterval(-420)
        docs.turnEndedAt = now.addingTimeInterval(-300)
        docs.toolCount = 9
        for page in 1...6 {
            docs.fileChanges.record(.modified, path: "/Users/demo/handbook/guide-\(page).md", linesAdded: 4, linesRemoved: 3)
        }

        return [api, web, docs]
    }

    /// Tool calls spread over the last hour in bursts, the way a session works.
    private static func toolUsage(now: Date, calls: [(String, Int)]) -> ToolUsage {
        var usage = ToolUsage()
        var step = 0
        for (tool, count) in calls {
            for _ in 0..<count {
                // Busy for the last ~15 minutes, a burst around half an hour ago, quiet otherwise.
                let minutesAgo = step % 3 == 0 ? 28 + step % 6 : step % 15
                usage.record(toolName: tool, at: now.addingTimeInterval(-Double(minutesAgo * 60 + 5)))
                step += 1
            }
        }
        return usage
    }

    /// Sample sessions for the Resume widget.
    static func pastSessions(now: Date = .now) -> [PastSession] {
        // Real folders, so the rows show as resumable; the last one is missing on purpose.
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("notchgate-demo")
        let orders = base.appendingPathComponent("orders-service").path
        let checkout = base.appendingPathComponent("checkout-api").path
        for folder in [orders, checkout] {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        return [
            PastSession(id: "demo-past-1", directory: orders, title: "Add pagination to the orders endpoint",
                        branch: "feature/orders-paging", updatedAt: now.addingTimeInterval(-25 * 60)),
            PastSession(id: "demo-past-2", directory: checkout, title: "Fix flaky checkout tests",
                        branch: "main", updatedAt: now.addingTimeInterval(-5 * 3600)),
            PastSession(id: "demo-past-3", directory: "/Users/demo/gone", title: "Prototype the onboarding flow",
                        branch: nil, updatedAt: now.addingTimeInterval(-3 * 86_400)),
        ]
    }
}
