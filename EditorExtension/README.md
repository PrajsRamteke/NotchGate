# NotchGate Bridge

Companion extension for [NotchGate](https://github.com/PrajsRamteke/NotchGate).
It lets the notch type prompts into the Claude Code session running in this
window's integrated terminal, so they arrive as real prompts, exactly as if you
had typed them.

- Works in Cursor, VS Code, VS Code Insiders, Windsurf and VSCodium on macOS.
- Listens only on a user-only Unix socket; nothing goes over the network.
- Types only into the terminal whose shell is running that Claude session.

Installed automatically by NotchGate's `install.sh`, or from the NotchGate menu.
After installing, reload open editor windows once.
