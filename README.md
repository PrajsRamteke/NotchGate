# NotchGate

A native macOS companion that answers **Claude Code** from your MacBook's notch.
When Claude needs permission, asks a question, wants a plan approved, or finishes
a task, a Dynamic Island–style card grows out of the notch. Respond in place
and keep working — no tab switching.

| Request | What you can do |
| --- | --- |
| Tool permission (`Bash`, `Edit`, `Write`, `WebFetch`, MCP tools…) | **Allow**, **Deny**, **Always allow**, or deny with a note |
| `AskUserQuestion` | Pick options (single / multi-select), write your own, or answer in terminal |
| Plan approval (`ExitPlanMode`) | **Approve** or **Keep planning** with feedback |
| MCP elicitation | Fill the server's form or open its link; decline / cancel |
| Claude stopped *(opt-in)* | Read the summary, optionally **reply to continue** |
| **Hover the notch** anytime | Live activity for every session: current step, to-do progress, elapsed time, last prompt. Click to jump to its terminal |

**Auto-allow permissions:** flip it from any permission card, the hover panel, or
the menu bar, and prompts are approved instantly with no card. Risky commands
(`rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `curl … | sh`, `DROP TABLE` …)
still ask unless you turn that safeguard off. Your Claude Code deny rules always apply.

**Claude's questions:** choose **Notch** (answer from the notch), **Terminal**
(the notch stays out of it), or **Don't ask** (Claude picks the most reasonable
option, states its assumption, and keeps going).

By default the notch appears **only when Claude is actually waiting on you**.
"Claude finished" notices and reply-to-continue are off by default and can be
turned on from the menu-bar popover.

## Requirements

- macOS 14+ (Apple silicon or Intel; works on displays without a notch too)
- Xcode 16+ / Swift 6 toolchain
- Claude Code with hooks support

## Install (one command)

```bash
git clone https://github.com/PrajsRamteke/NotchGate.git && cd NotchGate && ./install.sh
```

Or without cloning first:

```bash
curl -fsSL https://raw.githubusercontent.com/PrajsRamteke/NotchGate/main/install.sh | bash
```

The installer:

1. Checks for macOS 14+ and the Swift toolchain. If the toolchain is missing, it opens the Command Line Tools installer.
2. Builds `NotchGate.app` and installs it to `/Applications` (or `~/Applications` if that isn't writable).
3. Copies `notchgate-hook` to `~/.notchgate/bin/` and registers it in
   `~/.claude/settings.json`, saving a timestamped `.bak` first.
4. Warns about any other `PermissionRequest` hook that would race NotchGate.
5. Turns on launch at login and starts the app.

Then **restart any running Claude Code sessions**. Click the spark in the menu
bar → **Preview** to try every card without Claude.

Re-running the installer is safe; it updates in place. To remove everything:

```bash
./install.sh --uninstall
# or, without a clone:
curl -fsSL https://raw.githubusercontent.com/PrajsRamteke/NotchGate/main/install.sh | bash -s -- --uninstall
```

> **Already using another notch app for Claude (e.g. Claude Island)?** Remove its
> `PermissionRequest` hook. Two apps answering the same prompt will race. The
> installer flags any it finds.

## Keyboard

| Shortcut | Action |
| --- | --- |
| `⏎` / `⎋` | Primary / cancel action when the card has focus |
| `⌃⌥⏎` | Allow / approve (global, only while a request waits) |
| `⌃⌥⌫` | Deny / reject (global) |
| `⌃⌥Space` | Expand or minimize the island (global) |

Clicking buttons never steals focus from the app you're in. The panel is
non-activating, and hotkeys use Carbon, so no Accessibility permission is needed.

## How it works

```
Claude Code ──stdin JSON──▶ notchgate-hook ──Unix socket──▶ NotchGate.app
            ◀─stdout JSON──                ◀──decision────   (notch island)
```

1. Claude Code runs `notchgate-hook` for each subscribed hook event.
2. The hook forwards the payload over `~/Library/Application Support/NotchGate/bridge.sock`
   (`0600`, user-only) as one line of JSON, then waits for a reply when the event needs one.
3. The app routes the payload into a typed request, shows the matching card,
   and sends the decision back. `HookOutput` converts it into the exact JSON
   Claude Code expects.
4. **It fails open:** if the app isn't running, or anything goes wrong, the hook
   exits silently and Claude shows its normal terminal prompt. If you answer
   in the terminal instead, the hook process ends and the card dismisses itself.

| Hook event | Used for | Blocks? |
| --- | --- | --- |
| `PermissionRequest` | Tool permission cards | yes |
| `PreToolUse` (all tools) | Questions and plan approval; live activity for every other tool | only for questions/plans |
| `Elicitation` | MCP forms / links | yes |
| `Stop` | Clears stale cards; optional notice / reply-to-continue | briefly |
| `PostToolUse` | Clears a card once its tool ran (approved in terminal, auto mode…) | no |
| `Notification` | "Claude is waiting" notices | no |
| `UserPromptSubmit`, `SessionStart`, `SessionEnd`, `PreCompact` | Live activity; clear stale cards | no |

## Project structure

Organized by feature; every file stays well under 300 lines.

```
Sources/
├── NotchGateKit/                 Shared by app + hook (no UI)
│   ├── Protocol/                 JSONValue, HookEvent, HookPolicy, BridgeMessage, HookOutput
│   └── Transport/                UnixSocket, LineFramer, BridgeLocation
├── NotchGateHook/                The CLI Claude Code invokes
│   ├── main.swift · HookRunner.swift · BridgeClient.swift
└── NotchGate/                    The menu-bar app
    ├── App/                      Entry point, AppCoordinator (composition root)
    ├── Core/
    │   ├── Activity/             Live session state: reducer, tracker, tool summaries
    │   ├── Bridge/               Socket server + per-hook connection
    │   ├── Requests/             Domain models, PayloadParsers, RequestRouter, RequestStore
    │   ├── Hooks/                settings.json editor (pure) + installer (I/O)
    │   ├── Settings/             AppSettings (UserDefaults)
    │   └── System/               Hotkeys, sound, launch-at-login, terminal activation
    ├── Features/
    │   ├── Island/               Window (panel, metrics, click-through) + views + view model
    │   ├── Permission/           Card, ToolDescriptor, tool & diff previews
    │   ├── Question/             Card, form model, option rows
    │   ├── Activity/             Hover panel: session rows, task progress bar
    │   ├── Plan/ · Elicitation/ · Completion/ · Notice/
    │   └── MenuBar/              Popover, sections, template icon
    ├── DesignSystem/             Theme, ClaudeSpark, buttons, fields, markdown, code blocks
    └── Support/                  Logging, demo requests, snapshot renderer
Tests/
├── NotchGateKitTests/            Hook output contract, framing, sockets
└── NotchGateTests/               Router, settings editor, form models, parsers
```

## Development

```bash
make test                                     # 44 unit tests
make run                                      # run from source
.build/debug/NotchGate --snapshot ./shots     # render every card to PNG offscreen
log stream --predicate 'subsystem == "app.notchgate"'
NOTCHGATE_DEBUG=1 NOTCHGATE_SOCKET=/tmp/ng.sock   # hook debugging overrides
```

## Known limits

- Answering `AskUserQuestion` and `ExitPlanMode` through `PreToolUse` +
  `updatedInput` is documented by Claude Code. Approving a plan this way has
  not been confirmed against every Claude Code version; if it doesn't work,
  **Keep planning** and **Answer in terminal** still do.
- Claude Code only loads hooks in trusted folders, and only when a session starts.
