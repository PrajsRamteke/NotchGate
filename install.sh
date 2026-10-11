#!/usr/bin/env bash
# NotchGate one-command installer.
#
#   ./install.sh               build, install, connect to Claude Code, launch
#   ./install.sh --uninstall   remove hooks, login item, app and hook binary
#
# Works from a cloned repo (builds it), or piped from curl (downloads the
# prebuilt app, building from source only as a fallback):
#   curl -fsSL https://raw.githubusercontent.com/PrajsRamteke/NotchGate/main/install.sh | bash
#   curl -fsSL …/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO_URL="${NOTCHGATE_REPO:-https://github.com/PrajsRamteke/NotchGate.git}"
RAW_INSTALLER="https://raw.githubusercontent.com/PrajsRamteke/NotchGate/main/install.sh"
RELEASE_URL="${NOTCHGATE_RELEASE_URL:-https://github.com/PrajsRamteke/NotchGate/releases/download/latest}"
APP_NAME="NotchGate.app"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
step() { printf "\033[38;5;173m→\033[0m %s\n" "$1"; }
ok()   { printf "\033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[33m⚠\033[0m %s\n" "$1"; }
fail() { printf "\033[31m✗\033[0m %s\n" "$1" >&2; exit 1; }

installed_app() {
    for dir in /Applications "$HOME/Applications"; do
        [[ -d "$dir/$APP_NAME" ]] && { echo "$dir/$APP_NAME"; return 0; }
    done
    return 0
}

quit_running_app() {
    # -a: include ancestors (pkill skips them by default); anchored to the executable path.
    pkill -a -f '^[^ ]*/NotchGate\.app/Contents/MacOS/NotchGate( |$)' 2>/dev/null || true
    sleep 0.5
}

# ── Uninstall ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    bold "Uninstalling NotchGate"
    APP="$(installed_app || true)"
    [[ -n "$APP" ]] && "$APP/Contents/MacOS/NotchGate" --uninstall || warn "App not found; skipping hook removal"
    quit_running_app
    [[ -n "$APP" ]] && rm -rf "$APP"
    rm -rf "$HOME/.notchgate"
    ok "NotchGate removed. Restart Claude Code sessions to drop the hooks."
    exit 0
fi

# Downloads the prebuilt app from the "latest" release (published by
# .github/workflows/release.yml) and prints its path. Fails quietly on any
# problem so the caller can fall back to building from source.
download_prebuilt() {
    local tmp app binary
    tmp="$(mktemp -d)"
    curl -fsL --retry 2 -o "$tmp/NotchGate.zip" "$RELEASE_URL/NotchGate.zip" || return 1
    curl -fsL --retry 2 -o "$tmp/NotchGate.zip.sha256" "$RELEASE_URL/NotchGate.zip.sha256" || return 1
    [[ "$(shasum -a 256 "$tmp/NotchGate.zip" | awk '{print $1}')" == "$(tr -d '[:space:]' < "$tmp/NotchGate.zip.sha256")" ]] || return 1
    ditto -x -k "$tmp/NotchGate.zip" "$tmp" || return 1
    app="$tmp/$APP_NAME"
    binary="$app/Contents/MacOS/NotchGate"
    [[ -x "$binary" ]] || return 1
    # `file`, not `lipo`: lipo needs the Command Line Tools, which this path avoids.
    file "$binary" | grep -q "$(uname -m)" || return 1
    codesign --verify --deep --strict "$app" 2>/dev/null || return 1
    echo "$app"
}

# Replaces the installed app (wherever it lives) with $1.
install_bundle() {
    local target dir
    target="$(installed_app)"
    if [[ -z "$target" ]]; then
        # /Applications needs admin rights on some Macs; fall back to ~/Applications.
        dir="${NOTCHGATE_INSTALL_DIR:-/Applications}"
        [[ -w "$dir" ]] || { dir="$HOME/Applications"; mkdir -p "$dir"; }
        target="$dir/$APP_NAME"
    fi
    quit_running_app
    rm -rf "$target"
    ditto "$1" "$target"
    ok "Installed $target"
}

bold "Installing NotchGate"

# ── Preflight ────────────────────────────────────────────────────────────────
step "Checking requirements"
[[ "$(uname -s)" == "Darwin" ]] || fail "NotchGate runs on macOS only."

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
(( macos_major >= 14 )) || fail "macOS 14 or newer is required (found $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

if command -v claude >/dev/null 2>&1; then
    ok "Claude Code found ($(claude --version 2>/dev/null | head -1))"
else
    warn "Claude Code CLI not found. Hooks will still be installed for when you add it."
fi

# ── Get the app ──────────────────────────────────────────────────────────────
# From a clone, build that checkout (your local changes). Piped from curl, use the
# prebuilt release; build from source only if it's unavailable or
# NOTCHGATE_FROM_SOURCE=1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Package.swift" ]]; then
    ROOT="$SCRIPT_DIR"
    UNINSTALL_HINT="./install.sh --uninstall"
else
    ROOT=""
    UNINSTALL_HINT="curl -fsSL $RAW_INSTALLER | bash -s -- --uninstall"
fi

PREBUILT=""
if [[ -z "$ROOT" && "${NOTCHGATE_FROM_SOURCE:-}" != "1" ]]; then
    step "Downloading NotchGate"
    if PREBUILT="$(download_prebuilt)"; then
        install_bundle "$PREBUILT"
    else
        PREBUILT=""
        warn "Prebuilt download unavailable; building from source instead."
    fi
fi

if [[ -z "$PREBUILT" ]]; then
    if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
        warn "Building needs the Swift toolchain. Opening the Command Line Tools installer…"
        xcode-select --install 2>/dev/null || true
        fail "Re-run this script after the Command Line Tools finish installing."
    fi
    if [[ -z "$ROOT" ]]; then
        command -v git >/dev/null 2>&1 || fail "git is required to download NotchGate."
        ROOT="$(mktemp -d)/NotchGate"
        step "Downloading source"
        git clone --depth 1 "$REPO_URL" "$ROOT" >/dev/null 2>&1 || fail "Could not clone $REPO_URL"
    fi
    cd "$ROOT"
    step "Building (first build takes a minute)"
    "$ROOT/Scripts/bundle.sh" --install | grep -E "✓" || fail "Build failed. Run Scripts/bundle.sh to see the full output."
fi

APP="$(installed_app)"
[[ -n "$APP" ]] || fail "Installed app not found."

# ── Connect to Claude Code ───────────────────────────────────────────────────
step "Connecting to Claude Code"
"$APP/Contents/MacOS/NotchGate" --setup

step "Launching"
open "$APP"

echo
bold "NotchGate is ready ✦"
cat <<EOF
  • Restart any running Claude Code sessions to load the hooks.
  • Look for the spark in your menu bar → Preview shows every card.
  • Shortcuts while a request waits: ⌃⌥⏎ allow · ⌃⌥⌫ deny · ⌃⌥Space show/hide
  • Remove everything later with: $UNINSTALL_HINT
EOF
