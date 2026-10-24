#!/usr/bin/env bash
# `make run`: builds the debug app and runs it as "dist/NotchGate Dev.app".
#
# macOS grants the microphone (Notch Voice) and Accessibility only to apps opened as
# apps, never to a binary started from a terminal, so the debug build is wrapped in a
# bundle and opened with `open`. Its log streams here; Ctrl-C quits it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/NotchGate Dev.app"
cd "$ROOT"

quit_dev() {
    pkill -f "NotchGate Dev\.app/Contents/MacOS/NotchGate" 2>/dev/null || true
    # An older `make run` ran the bare binary.
    pkill -f '(^|/)\.build/(arm64-apple-macosx/|x86_64-apple-macosx/)?debug/NotchGate$' 2>/dev/null || true
}

# Only one NotchGate can own the notch, the Claude Code bridge and the voice shortcut.
if pgrep -f '/NotchGate\.app/Contents/MacOS/NotchGate( |$)' >/dev/null; then
    echo "→ Quitting the installed NotchGate while the dev build runs (open it again afterwards)"
    osascript -e 'tell application id "app.notchgate.NotchGate" to quit' >/dev/null 2>&1 || true
fi
quit_dev
"$ROOT/Scripts/bundle.sh" --dev

LOG_PID=""
cleanup() {
    quit_dev
    [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log stream --style compact --predicate 'subsystem == "app.notchgate"' &
LOG_PID=$!

MARKER="$(mktemp -t notchgate-run)"
echo "→ Running NotchGate Dev (Ctrl-C quits). Notch Voice: ✦ → Notch Voice."
open -W "$APP"

# The app ended without Ctrl-C: say so, and point at the crash report if there is one.
REPORT="$(find "$HOME/Library/Logs/DiagnosticReports" -name 'NotchGate-*.ips' -newer "$MARKER" 2>/dev/null | sort | tail -1)"
rm -f "$MARKER"
if [[ -n "$REPORT" ]]; then
    echo "✗ NotchGate Dev crashed. Report: $REPORT"
    exit 1
fi
echo "• NotchGate Dev quit."
