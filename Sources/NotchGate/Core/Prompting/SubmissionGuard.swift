import Foundation

/// Makes sure a typed prompt was actually submitted.
///
/// Claude Code sometimes drops the Return that follows a paste, leaving the
/// prompt sitting in its input box. The `UserPromptSubmit` hook is proof the
/// prompt went in; when it doesn't arrive, Return is pressed again. That is
/// harmless if the first one landed late: Return on an empty input does nothing.
enum SubmissionGuard {
    static let pollInterval: Duration = .milliseconds(100)
    /// Time for the hook to reach us (it's a process spawn plus a socket hop).
    static let waitForProof: Duration = .milliseconds(1_200)
    static let maxRetries = 2

    /// - Returns: whether the prompt was seen to be submitted.
    @MainActor
    static func ensureSubmitted(
        isSubmitted: () -> Bool,
        pressReturn: () async throws -> Void,
        sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Bool {
        for attempt in 0...maxRetries {
            var waited: Duration = .zero
            while waited < waitForProof {
                if isSubmitted() { return true }
                await sleep(pollInterval)
                waited += pollInterval
            }
            if isSubmitted() { return true }
            guard attempt < maxRetries else { break }
            do {
                try await pressReturn()
                Log.app.info("Prompt wasn't submitted; pressed Return again (retry \(attempt + 1))")
            } catch {
                return false // The terminal is gone or unreachable; nothing more to try.
            }
        }
        return false
    }
}
