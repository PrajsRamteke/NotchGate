#!/usr/bin/env bash
# Builds a release NotchGate.app into ./dist (ad-hoc signed).
#
#   Scripts/bundle.sh            # build dist/NotchGate.app
#   Scripts/bundle.sh --install  # …and copy it to /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/NotchGate.app"
CONFIG="release"

cd "$ROOT"
echo "→ Building ($CONFIG)…"
swift build -c "$CONFIG" --product NotchGate
swift build -c "$CONFIG" --product notchgate-hook
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NotchGate" "$APP/Contents/MacOS/NotchGate"
cp "$BIN/notchgate-hook" "$APP/Contents/MacOS/notchgate-hook"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "→ Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/MacOS/notchgate-hook" 2>/dev/null
codesign --force --sign - "$APP" 2>/dev/null

if [[ "${1:-}" == "--install" ]]; then
    # /Applications needs admin rights on some Macs; fall back to ~/Applications.
    INSTALL_DIR="${NOTCHGATE_INSTALL_DIR:-/Applications}"
    if [[ ! -w "$INSTALL_DIR" ]]; then
        INSTALL_DIR="$HOME/Applications"
        mkdir -p "$INSTALL_DIR"
    fi
    echo "→ Installing to $INSTALL_DIR"
    rm -rf "$INSTALL_DIR/NotchGate.app"
    cp -R "$APP" "$INSTALL_DIR/NotchGate.app"
    echo "✓ Installed $INSTALL_DIR/NotchGate.app"
else
    echo "✓ Built $APP"
fi
