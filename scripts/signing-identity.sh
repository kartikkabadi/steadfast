#!/bin/bash
# The private release key stays in a dedicated keychain.
set -euo pipefail

NAME="Steadfast Release"
KEYCHAIN="$HOME/Library/Keychains/steadfast-signing.keychain-db"
PASS_SERVICE="steadfast-signing-keychain"

keychain_password() {
  security find-generic-password -a "$USER" -s "$PASS_SERVICE" -w 2>/dev/null
}

unlock() {
  security unlock-keychain -p "$(keychain_password)" "$KEYCHAIN"
  # Keep it unlocked for an hour so a long build doesn't stall on a prompt.
  security set-keychain-settings -t 3600 -l "$KEYCHAIN"
}

if [ -f "$KEYCHAIN" ] && keychain_password >/dev/null; then
  unlock
  if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "$KEYCHAIN"
    exit 0
  fi
fi

[ -f "$KEYCHAIN" ] && { echo "error: $KEYCHAIN exists but has no usable \"$NAME\" identity. Restore it from your backup." >&2; exit 1; }

[[ "${1:-}" == "--create" ]] || { echo "no steadfast release key. run scripts/signing-identity.sh --create once." >&2; exit 1; }
umask 077
echo "==> Creating the \"$NAME\" signing identity (one time)" >&2
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = Steadfast
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

# Twenty years: the certificate must outlive every release signed with it.
openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -sha256 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PASS=$(openssl rand -hex 16)
# macOS only imports the older PKCS#12 ciphers; OpenSSL 3 needs -legacy for them, LibreSSL has no such flag.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -passout "pass:$P12_PASS" -out "$WORK/identity.p12" 2>/dev/null \
  || /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -passout "pass:$P12_PASS" -out "$WORK/identity.p12"

KC_PASS=$(openssl rand -hex 24)
security add-generic-password -U -a "$USER" -s "$PASS_SERVICE" -w "$KC_PASS" \
  -D "Steadfast signing keychain password"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
unlock
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without a password dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\"" \
  || { echo "error: the new identity is not usable for code signing" >&2; exit 1; }
echo "    created. Back up $KEYCHAIN (and its password, service \"$PASS_SERVICE\" in the login keychain)." >&2
echo "$KEYCHAIN"
