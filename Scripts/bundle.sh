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
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Record the source commit so the app can tell when GitHub has something newer.
COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Add :NotchGateCommit string $COMMIT" "$APP/Contents/Info.plist"
"$ROOT/Scripts/build-vsix.sh" "$APP/Contents/Resources/notchgate-bridge.vsix" >/dev/null

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
    # Quit only now, after the build succeeded, so updates keep the app usable until the swap.
    # -a: during an in-app update NotchGate is our ancestor, which pkill skips by default.
    # Anchored to the executable path so it can't match a shell whose arguments mention it.
    pkill -a -f '^[^ ]*/NotchGate\.app/Contents/MacOS/NotchGate( |$)' 2>/dev/null || true
    sleep 0.5
    rm -rf "$INSTALL_DIR/NotchGate.app"
    cp -R "$APP" "$INSTALL_DIR/NotchGate.app"
    echo "✓ Installed $INSTALL_DIR/NotchGate.app"
else
    echo "✓ Built $APP"
fi
