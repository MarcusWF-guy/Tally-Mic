#!/bin/bash
# Creates the "Tally Local" code-signing certificate if it doesn't exist yet (SPEC 9).
# build.sh runs this for you. Tally Cam can sign with the same certificate.
#
# macOS remembers an app by its signature. Signing every build with the same certificate keeps
# that signature stable, so the login item stays registered across rebuilds.
set -euo pipefail

name="Tally Local"
keychain="${TALLY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if /usr/bin/security find-identity -p codesigning "$keychain" | grep -q "\"$name\""; then
    echo "The \"$name\" certificate already exists. Nothing to do."
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no

[dn]
CN = $name

[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

# /usr/bin/openssl on purpose: macOS can't import the .p12 files newer OpenSSL versions make.
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$work/cert.conf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

export_password="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$name" -out "$work/identity.p12" -passout "pass:$export_password"

/usr/bin/security import "$work/identity.p12" -k "$keychain" -P "$export_password" \
    -T /usr/bin/codesign >/dev/null

# Prove it works by signing a throwaway copy of a small system tool.
cp /usr/bin/true "$work/signing-check"
/usr/bin/codesign --force --sign "$name" --keychain "$keychain" "$work/signing-check" 2>/dev/null
/usr/bin/codesign --verify "$work/signing-check"

echo
echo "Done. The \"$name\" certificate is ready."
