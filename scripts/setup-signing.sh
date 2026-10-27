#!/bin/bash
set -euo pipefail
umask 077

# A per-user, per-app identity. Never put this directory or its keychain in Git.
signing_directory="$HOME/Library/Application Support/Mac Screen Recorder/Signing"
signing_keychain="$signing_directory/local-signing.keychain-db"
password_file="$signing_directory/keychain-password"
identity_file="$signing_directory/identity-sha1"

if [ ! -f "$identity_file" ]; then
    if [ -e "$signing_keychain" ] || [ -e "$password_file" ]; then
        printf 'Incomplete signing setup in %s. Restore it before continuing; do not replace an existing signing identity.\n' "$signing_directory" >&2
        exit 1
    fi
    mkdir -p "$signing_directory"
    chmod 700 "$signing_directory"
    temporary_directory="$(mktemp -d "$signing_directory/setup.XXXXXX")"
    trap 'rm -rf "$temporary_directory"' EXIT
    /usr/bin/openssl rand -hex 32 > "$password_file"
    signing_password="$(cat "$password_file")"
    cat > "$temporary_directory/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = Mac Screen Recorder Local Signing
O = Mac Screen Recorder Local Development
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CONFIG
    /usr/bin/openssl req -new -x509 -newkey rsa:3072 -nodes -days 36500 \
        -config "$temporary_directory/certificate.cnf" \
        -keyout "$temporary_directory/private-key.pem" \
        -out "$temporary_directory/certificate.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export \
        -inkey "$temporary_directory/private-key.pem" \
        -in "$temporary_directory/certificate.pem" \
        -out "$temporary_directory/identity.p12" -passout "file:$password_file"
    security create-keychain -p "$signing_password" "$signing_keychain" >/dev/null
    security set-keychain-settings -lut 300 "$signing_keychain"
    security unlock-keychain -p "$signing_password" "$signing_keychain"
    security import "$temporary_directory/identity.p12" -k "$signing_keychain" \
        -P "$signing_password" -x -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s \
        -k "$signing_password" "$signing_keychain" >/dev/null
    /usr/bin/openssl x509 -in "$temporary_directory/certificate.pem" -outform DER \
        -out "$signing_directory/certificate.cer"
    /usr/bin/openssl x509 -in "$temporary_directory/certificate.pem" -fingerprint -sha1 -noout \
        | sed 's/.*=//; s/://g' > "$identity_file"
    printf 'Created persistent local signing identity.\n' >&2
fi

signing_password="$(cat "$password_file")"
security unlock-keychain -p "$signing_password" "$signing_keychain"
identity="$(cat "$identity_file")"
if ! security find-identity -p codesigning "$signing_keychain" | /usr/bin/grep -F "$identity" >/dev/null; then
    printf 'Saved signing identity is missing from %s. Restore the original signing directory.\n' "$signing_keychain" >&2
    exit 1
fi
# Trust this one self-signed certificate for code signing in the current user's
# trust settings. No system roots, TLS trust, or Gatekeeper settings are changed.
if ! security find-identity -v -p codesigning "$signing_keychain" | /usr/bin/grep -F "$identity" >/dev/null; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$signing_keychain" \
        "$signing_directory/certificate.cer"
fi
if ! security find-identity -v -p codesigning "$signing_keychain" | /usr/bin/grep -F "$identity" >/dev/null; then
    printf 'The saved certificate is not available for code signing.\n' >&2
    exit 1
fi
# stdout is consumed by build.sh; diagnostics stay on stderr.
printf '%s\n' "$identity"
