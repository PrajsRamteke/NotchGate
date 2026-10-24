#!/usr/bin/env bash
# Prints the keychain holding "NotchGate Dev", a self-signed code-signing identity for
# local builds, creating both the first time. Used by `Scripts/bundle.sh --dev`.
#
# macOS ties Accessibility and microphone permission to an app's code signature. An
# ad-hoc signature is a hash of the build itself, so every rebuild looks like a new app
# and loses its permissions. Signing with a fixed identity keeps them.
#
# The identity lives in its own keychain (~/Library/Keychains/notchgate-dev.keychain-db),
# not the login keychain, so signing never asks for a password. Its password only guards
# this throwaway local key. Remove everything with: Scripts/dev-identity.sh --remove
set -euo pipefail

NAME="NotchGate Dev"
KEYCHAIN="$HOME/Library/Keychains/notchgate-dev.keychain-db"
PASSWORD="notchgate-dev"
# Apple's LibreSSL writes PKCS#12 files that `security import` reads; OpenSSL 3 doesn't by default.
OPENSSL=/usr/bin/openssl

if [[ "${1:-}" == "--remove" ]]; then
    security delete-keychain "$KEYCHAIN" 2>/dev/null && echo "✓ Removed $KEYCHAIN" || echo "• Nothing to remove"
    exit 0
fi

has_identity() {
    security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1
}

if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$PASSWORD" "$KEYCHAIN"
    # No auto-lock: builds keep working after the Mac sleeps.
    security set-keychain-settings "$KEYCHAIN"
fi
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

if ! has_identity; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.conf" \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
    "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$NAME" -out "$WORK/identity.p12" -passout pass:"$PASSWORD"
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
    # Let codesign use the key without a prompt.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
    echo "→ Created the \"$NAME\" signing identity (one time)" >&2
fi

echo "$KEYCHAIN"
