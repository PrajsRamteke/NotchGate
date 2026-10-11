import Foundation

// `notchgate-hook` — invoked by Claude Code for each subscribed hook event.
// It must never break a Claude session: every failure path exits 0 silently,
// which hands control back to Claude Code's built-in terminal prompts.
exit(HookRunner().run())
