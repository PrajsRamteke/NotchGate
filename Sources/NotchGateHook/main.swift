import Foundation

// `notchgate-hook` — invoked by Claude Code for each subscribed hook event.
// It must never break a Claude session: every failure path exits 0 silently,
// which hands control back to Claude Code's built-in terminal prompts.
//
// With `--statusline` it's Claude Code's status line command instead (see
// `StatusLineRelay`), installed only while the Usage widget is on.
if CommandLine.arguments.contains("--statusline") {
    exit(StatusLineRelay().run())
}
exit(HookRunner().run())
