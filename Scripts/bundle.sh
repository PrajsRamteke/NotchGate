#!/usr/bin/env bash
# Builds a release NotchGate.app into ./dist (ad-hoc signed).
#
#   Scripts/bundle.sh            # build dist/NotchGate.app
#   Scripts/bundle.sh --install  # …and copy it to /Applications
#   Scripts/bundle.sh --dev      # debug build as "dist/NotchGate Dev.app" (see make run)
#
# NOTCHGATE_UNIVERSAL=1 builds for Apple silicon and Intel (needs Xcode); the
# release workflow uses it for the prebuilt download.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/NotchGate.app"
CONFIG="release"
# The dev bundle has its own bundle ID, so its settings and macOS permissions stay
# apart from the installed app's, and it never offers updates or joins login items.
DEV=""
if [[ "${1:-}" == "--dev" ]]; then
    DEV=1
    CONFIG="debug"
    APP="$DIST/NotchGate Dev.app"
fi
BUILD_FLAGS=(-c "$CONFIG")
[[ "${NOTCHGATE_UNIVERSAL:-}" == "1" ]] && BUILD_FLAGS+=(--arch arm64 --arch x86_64)

cd "$ROOT"
echo "→ Building ($CONFIG)…"
swift build "${BUILD_FLAGS[@]}" --product NotchGate
swift build "${BUILD_FLAGS[@]}" --product notchgate-hook
swift build "${BUILD_FLAGS[@]}" --product NotchGateMedia
BIN="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NotchGate" "$APP/Contents/MacOS/NotchGate"
cp "$BIN/notchgate-hook" "$APP/Contents/MacOS/notchgate-hook"
# Loaded into /usr/bin/perl for Now Playing (see NowPlayingMonitor).
cp "$BIN/libNotchGateMedia.dylib" "$APP/Contents/MacOS/libNotchGateMedia.dylib"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "$DEV" ]]; then
    for entry in "Set :CFBundleIdentifier app.notchgate.NotchGate.dev" \
                 "Set :CFBundleName NotchGate Dev" \
                 "Set :CFBundleDisplayName NotchGate Dev" \
                 "Add :NotchGateDevBuild bool true"; do
        /usr/libexec/PlistBuddy -c "$entry" "$APP/Contents/Info.plist"
    done
else
    # Record the source commit so the app can tell when GitHub has something newer.
    COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    /usr/libexec/PlistBuddy -c "Add :NotchGateCommit string $COMMIT" "$APP/Contents/Info.plist"
    "$ROOT/Scripts/build-vsix.sh" "$APP/Contents/Resources/notchgate-bridge.vsix" >/dev/null
fi

# The dev build signs with a fixed local identity, so macOS keeps its Accessibility and
# microphone permission across rebuilds (an ad-hoc signature changes with every build).
SIGN=(--sign -)
if [[ -n "$DEV" ]] && KEYCHAIN="$("$ROOT/Scripts/dev-identity.sh")"; then
    SIGN=(--sign "NotchGate Dev" --keychain "$KEYCHAIN")
    echo "→ Signing (NotchGate Dev identity)"
else
    echo "→ Signing (ad-hoc)"
fi
codesign --force "${SIGN[@]}" "$APP/Contents/MacOS/notchgate-hook" 2>/dev/null
codesign --force "${SIGN[@]}" "$APP/Contents/MacOS/libNotchGateMedia.dylib" 2>/dev/null
codesign --force "${SIGN[@]}" "$APP" 2>/dev/null

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
